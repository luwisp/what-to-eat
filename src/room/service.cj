package huaiwei.room

import huaiwei.model.*
import huaiwei.store.*
import huaiwei.platform.*
import huaiwei.agent.*
import stdx.crypto.crypto.*

public enum RoomCommand {
    UpdatePreferences(Preferences, Bool)
    | AddCompanion(Preferences, String)
    | UpdateCompanion(String, Preferences, String)
    | RemoveCompanion(String)
    | UpdateSession(Int64, ?Int64)
    | Confirm(String, Int64)
    | Reopen
}

public class RoomFault <: Exception {
    public let error: DomainError
    public init(code: String, message: String, status!: UInt16 = 400) {
        super(message)
        error = DomainError(code, message, status: status)
    }
}

public func demand(ok: Bool, code: String, message: String, status!: UInt16 = 400): Unit {
    if (!ok) {
        throw RoomFault(code, message, status: status)
    }
}

public func newId(): String {
    let alphabet = "0123456789ABCDEF"
    var result = ""
    for (b in SecureRandom(priv: true).nextBytes(16)) {
        let high = Int64(b / 16)
        let low = Int64(b % 16)
        result += alphabet[high..high + 1] + alphabet[low..low + 1]
    }
    result
}

public func roomMenu(db: DatabaseSnapshot, session: Session): MenuSnapshot {
    for (r in db.restaurants) {
        if (r.id == session.restaurantId) {
            var version: Int64 = 0
            for (v in db.menuVersions) {
                if (v.restaurantId == r.id) {
                    version = v.menuVersion
                }
            }
            return MenuSnapshot(restaurant: r, menuVersion: version,
                dishes: db.dishes.filter({d => d.restaurantId == r.id}),
                setMeals: db.setMeals.filter({m => m.restaurantId == r.id}))
        }
    }
    throw RoomFault("NOT_FOUND", "餐馆不存在", status: 404)
}

public func roomByCode(db: DatabaseSnapshot, code: String, now: Int64): Session {
    for (s in db.sessions) {
        if (s.roomCode == code) {
            demand(now < s.expiresAt, "ROOM_EXPIRED", "聚餐局已过期", status: 410)
            return s
        }
    }
    throw RoomFault("NOT_FOUND", "聚餐局不存在", status: 404)
}

public func roomMember(db: DatabaseSnapshot, session: Session, actor: Actor): Participant {
    demand(actor.visitorId.isSome(), "VISITOR_REQUIRED", "请先建立访客会话", status: 401)
    for (p in db.participants) {
        if (p.sessionId == session.id && p.source == "self" && p.visitorId == actor.visitorId) {
            return p
        }
    }
    throw RoomFault("NOT_A_MEMBER", "请先加入聚餐局", status: 403)
}

public func invalidateRoom(db: DatabaseSnapshot, s: Session): Unit {
    s.stateVersion++
    s.recommendationInvalid = true
    if (s.state == "recommended") {
        s.state = "open"
    }
    for (r in db.recommendations) {
        if (r.sessionId == s.id) {
            r.canConfirm = false
            r.accepted = false
        }
    }
    for (job in db.jobs) {
        if (job.sessionId == s.id && job.status == "inProgress") {
            job.status = "cancelled"
        }
    }
}

public func roomSnapshot(db: DatabaseSnapshot, s: Session, actor: Actor): RoomSnapshot {
    let me = roomMember(db, s, actor)
    let views = db.participants.filter({p => p.sessionId == s.id}).map({
        p => ParticipantView(id: p.id, nickname: p.nickname, avatarColor: p.avatarColor, submitted: p.submitted,
            preferences: if (p.submitted) {
                Some(Preferences.fromJson(p.preferences.toJson()))
            } else {
                None
            }, source: p.source, filledByParticipantId: p.filledByParticipantId)
    })
    var recommendation: ?Recommendation = None
    for (r in db.recommendations) {
        if (r.sessionId == s.id) {
            recommendation = Some(Recommendation.fromJson(r.toJson()))
        }
    }
    let latestMenu = roomMenu(db, s)
    var invalid = s.recommendationInvalid
    if (let Some(r) <- recommendation) {
        invalid = invalid || r.menuVersion != latestMenu.menuVersion || (s.state != "closed" && r.roomVersion != s
            .stateVersion)
        if (invalid) {
            r.canConfirm = false
            r.accepted = false
        }
    }
    var job: ?RecommendationJob = None
    for (j in db.jobs) {
        if (j.sessionId == s.id && j.status == "inProgress") {
            job = Some(RecommendationJob.fromJson(j.toJson()))
        }
    }
    // No visitor mappings, account credentials or other people's drafts leave here.
    return RoomSnapshot(session: Session.fromJson(s.toJson()), restaurantCode: roomMenu(db, s)
        .restaurant
        .restaurantCode, stateVersion: s.stateVersion, menuVersion: latestMenu.menuVersion, members: views,
        self: Some(Participant.fromJson(me.toJson())), recommendation: recommendation, recommendationInvalid: invalid,
        job: job, messages: db.chatMessages.filter({m => m.sessionId == s.id}))
}

public func checkPreferences(p: Preferences): Unit {
    demand(["none", "ovoLacto", "plant"].contains(p.dietMode), "INVALID_PREFERENCES", "饮食模式无效")
    if (let Some(level) <- p.maxSpiceLevel) {
        demand(validateSpice(level).isOk(), "INVALID_PREFERENCES", "辣度无效")
    }
    demand(p.note.toRuneArray().size <= 200, "INVALID_PREFERENCES", "文字补充最多200字")
    for (values in [p.allergens, p.avoidFoods, p.tastePreferences, p.wantedDishIds, p.wantedSetMealIds]) {
        demand(values.size <= 100, "INVALID_PREFERENCES", "选项过多")
        for (v in values) {
            demand(!v.trimAscii().isEmpty() && v.size <= 256, "INVALID_PREFERENCES", "选项为空或过长")
        }
    }
}

func commandSignature(command: RoomCommand): String {
    match (command) {
        case UpdatePreferences(p, submit) => "prefs:${submit}:${p.toJson()}"
        case AddCompanion(p, name) => "add:${name}:${p.toJson()}"
        case UpdateCompanion(id, p, name) => "companion:${id}:${name}:${p.toJson()}"
        case RemoveCompanion(id) => "remove:${id}"
        case UpdateSession(people, budget) => "session:${people}:${budget}"
        case Confirm(id, version) => "confirm:${id}:${version}"
        case Reopen => "reopen"
    }
}

class RoomResult {
    public var value: ?RoomSnapshot = None
}

public class RoomService {
    public let repository: Repository
    public let clock: Clock
    public init(repository: Repository, clock: Clock) {
        this.repository = repository
        this.clock = clock
    }

    func transaction(action: (DatabaseSnapshot) -> RoomSnapshot): Outcome<RoomSnapshot> {
        let result = RoomResult()
        let committed = repository.transact({
            db => try {
                result.value = Some(action(db))
                Outcome.Ok(db)
            } catch (e: RoomFault) {
                Outcome.Err(e.error)
            } catch (_: Exception) {
                Outcome.Err(DomainError("INTERNAL_ERROR", "操作失败，未保存", status: 500))
            }
        })
        match (committed) {
            case Err(e) => Outcome.Err(e);
            case Ok(_) => Outcome.Ok(result.value.getOrThrow())
        }
    }
    func requestIdentity(actor: Actor, requestId: String): String {
        demand(actor.visitorId.isSome(), "VISITOR_REQUIRED", "请先建立访客会话", status: 401)
        demand(!requestId.isEmpty() && requestId.size <= 128, "INVALID_REQUEST_ID", "操作需要有效requestId")
        actor.visitorId.getOrThrow()
    }
    func replay(db: DatabaseSnapshot, scope: String, visitor: String, requestId: String, signature: String): ?String {
        for (r in db.dedupeRecords) {
            if (r.scope == scope && r.actorId == visitor && r.requestId == requestId && r.expiresAt > clock.wallMillis()) {
                demand(r.operation == signature, "REQUEST_ID_REUSED", "同一requestId不能用于不同操作", status: 409)
                return Some(r.resultJson)
            }
        }
        None
    }
    func remember(db: DatabaseSnapshot, scope: String, visitor: String, requestId: String, signature: String,
        code: String, expiry: Int64): Unit {
        db.dedupeRecords = db
            .dedupeRecords
            .concat(
                [DedupeRecord(scope: scope, actorId: visitor, requestId: requestId, operation: signature,
                    resultJson: code, expiresAt: expiry)])
    }
    func addSelf(db: DatabaseSnapshot, s: Session, actor: Actor): Participant {
        let count = db.participants.filter({p => p.sessionId == s.id}).size
        let p = Participant(id: newId(), sessionId: s.id, visitorId: actor.visitorId, userId: actor.userId,
            nickname: "成员 ${count + 1}", joinedAt: clock.wallMillis())
        if (let Some(uid) <- actor.userId) {
            for (d in db.defaultSettings) {
                if (d.userId == uid) {
                    p.draft = Preferences(allergens: d.allergens.clone(), avoidFoods: d.avoidFoods.clone(),
                        dietMode: d.dietMode, maxSpiceLevel: d.maxSpiceLevel,
                        tastePreferences: d.tastePreferences.clone())
                }
            }
        }
        db.participants = db.participants.concat([p])
        if (count + 1 > s.people) {
            s.people = count + 1
        }
        p
    }
    public func create(actor: Actor, input: CreateSessionInput, requestId: String): Outcome<RoomSnapshot> {
        transaction(
            {
                db =>
                    pruneExpiredData(db, clock.wallMillis())
                    let visitor = requestIdentity(actor, requestId)
                    let signature = input.toJson().toString()
                    if (let Some(code) <- replay(db, "create", visitor, requestId, signature)) {
                        return roomSnapshot(db, roomByCode(db, code, clock.wallMillis()), actor)
                    }
                    demand(input.people > 0 && input.people <= 100, "INVALID_PEOPLE", "人数须为1至100")
                    if (let Some(budget) <- input.budgetPerPersonFen) {
                        demand(budget >= 0 && budget <= Int64.Max / input.people, "INVALID_BUDGET", "预算无效")
                    }
                    var restaurant: ?Restaurant = None
                    for (r in db.restaurants) {
                        if (r.restaurantCode == input.restaurantCode) {
                            restaurant = Some(r)
                        }
                    }
                    demand(restaurant.isSome(), "NOT_FOUND", "餐馆不存在", status: 404)
                    var code = ""
                    for (_ in 0..32) {
                        let proposed = newId()[0..6]
                        if (!db.sessions.any({s => s.roomCode == proposed})) {
                            code = proposed
                            break
                        }
                    }
                    demand(!code.isEmpty(), "CODE_EXHAUSTED", "暂时无法分配房间码，请重试", status: 503)
                    let s = Session(id: newId(), roomCode: code, restaurantId: restaurant.getOrThrow().id,
                        people: input.people, budgetPerPersonFen: input.budgetPerPersonFen,
                        createdAt: clock.wallMillis(), expiresAt: clock.wallMillis() + 86400000)
                    s.menuVersion = roomMenu(db, s).menuVersion
                    db.sessions = db.sessions.concat([s])
                    let p = addSelf(db, s, actor)
                    s.hostParticipantId = p.id
                    remember(db, "create", visitor, requestId, signature, code, s.expiresAt)
                    roomSnapshot(db, s, actor)
            }
        )
    }
    public func join(actor: Actor, roomCode: String, nickname!: ?String = None): Outcome<RoomSnapshot> {
        transaction(
            {
                db =>
                    demand(actor.visitorId.isSome(), "VISITOR_REQUIRED", "请先建立访客会话", status: 401)
                    let s = roomByCode(db, roomCode, clock.wallMillis())
                    var existing: ?Participant = None
                    for (p in db.participants) {
                        if (p.sessionId == s.id && p.source == "self" && p.visitorId == actor.visitorId) {
                            existing = Some(p)
                        }
                    }
                    if (let Some(p) <- existing) {
                        if (actor.userId.isSome()) {
                            p.userId = actor.userId
                        }
                    } else {
                        demand(s.state != "closed", "ROOM_CLOSED", "聚餐局已定格，请发起人先重开", status: 409)
                        demand(db.participants.filter({p => p.sessionId == s.id}).size < 100, "ROOM_FULL",
                            "房间成员过多")
                        addSelf(db, s, actor)
                        invalidateRoom(db, s)
                    }
                    if (let Some(name) <- nickname) {
                        demand(!name.trimAscii().isEmpty() && name.toRuneArray().size <= 40, "INVALID_NICKNAME",
                            "昵称须为1至40字")
                        roomMember(db, s, actor).nickname = name.trimAscii()
                    }
                    roomSnapshot(db, s, actor)
            }
        )
    }
    public func snapshot(actor: Actor, roomCode: String): Outcome<RoomSnapshot> {
        try {
            let db = repository.read()
            Outcome.Ok(roomSnapshot(db, roomByCode(db, roomCode, clock.wallMillis()), actor))
        } catch (e: RoomFault) {
            Outcome.Err(e.error)
        }
    }
    public func apply(actor: Actor, roomCode: String, command: RoomCommand, expectedVersion: Int64, requestId: String): Outcome<RoomSnapshot> {
        transaction(
            {
                db =>
                    let visitor = requestIdentity(actor, requestId)
                    let s = roomByCode(db, roomCode, clock.wallMillis())
                    let me = roomMember(db, s, actor)
                    let signature = commandSignature(command)
                    if (replay(db, s.id, visitor, requestId, signature).isSome()) {
                        return roomSnapshot(db, s, actor)
                    }
                    demand(s.stateVersion == expectedVersion, "STALE_VERSION", "房间已变化，请使用最新状态重试",
                        status: 409)
                    match (command) {
                        case Reopen =>
                            demand(me.id == s.hostParticipantId, "FORBIDDEN", "只有发起人可重开", status: 403)
                            s.state = "open"
                            invalidateRoom(db, s)
                        case Confirm(id, version) =>
                            demand(me.id == s.hostParticipantId, "FORBIDDEN", "只有发起人可确认", status: 403)
                            demand(!s.recommendationInvalid && s.state == "recommended", "INVALID_RESULT", "请重新推荐",
                                status: 409)
                            let members = db.participants.filter({p => p.sessionId == s.id})
                            demand(members.size >= s.people && members.all({p => p.submitted}), "MEMBERS_INCOMPLETE",
                                "请先填写齐全", status: 409)
                            var found = false
                            for (r in db.recommendations) {
                                if (r.id == id && r.sessionId == s.id) {
                                    demand(
                                        r.roomVersion == version && version == s.stateVersion && r.menuVersion == roomMenu(
                                            db, s).menuVersion && r.draft.uncoveredIds.isEmpty(), "INVALID_RESULT",
                                        "方案已过期或仍有成员无菜", status: 409)
                                    r.accepted = true
                                    r.canConfirm = false
                                    found = true
                                }
                            }
                            demand(found, "NOT_FOUND", "方案不存在", status: 404)
                            s.state = "closed"
                            s.stateVersion++
                        case _ =>
                            demand(s.state != "closed", "ROOM_CLOSED", "请发起人先重开", status: 409)
                            var effective = true
                            match (command) {
                                case UpdatePreferences(p, submit) =>
                                    checkPreferences(p)
                                    me.draft = sanitizeWishes(roomMenu(db, s), p)
                                    if (submit) {
                                        me.preferences = Preferences.fromJson(me.draft.toJson())
                                        me.submitted = true
                                    } else {
                                        effective = false
                                    }
                                case AddCompanion(p, name) =>
                                    checkPreferences(p)
                                    let n = db.participants.filter({p => p.sessionId == s.id}).size
                                    demand(n < 100, "ROOM_FULL", "房间成员过多")
                                    db.participants = db
                                        .participants
                                        .concat(
                                            [Participant(id: newId(), sessionId: s.id,
                                                nickname: if (name.trimAscii().isEmpty()) {
                                                    "同行人 ${n + 1}"
                                                } else {
                                                    name
                                                }, submitted: true, preferences: sanitizeWishes(roomMenu(db, s), p),
                                                draft: sanitizeWishes(roomMenu(db, s), p), source: "companion",
                                                filledByParticipantId: Some(me.id), joinedAt: clock.wallMillis())])
                                    if (n + 1 > s.people) {
                                        s.people = n + 1
                                    }
                                case UpdateCompanion(id, p, name) =>
                                    checkPreferences(p)
                                    let target = ownedCompanion(db, s, me, id)
                                    target.preferences = sanitizeWishes(roomMenu(db, s), p)
                                    target.draft = sanitizeWishes(roomMenu(db, s), p)
                                    target.submitted = true
                                    if (!name.trimAscii().isEmpty()) {
                                        target.nickname = name
                                    }
                                case RemoveCompanion(id) =>
                                    ownedCompanion(db, s, me, id)
                                    db.participants = db.participants.filter({p => p.id != id})
                                case UpdateSession(people, budget) =>
                                    demand(me.id == s.hostParticipantId, "FORBIDDEN", "只有发起人可修改人数和预算",
                                        status: 403)
                                    demand(
                                        people >= db.participants.filter({p => p.sessionId == s.id}).size && people <=
                                            100, "INVALID_PEOPLE", "声明人数不能少于已登记人数")
                                    if (let Some(value) <- budget) {
                                        demand(value >= 0 && value <= Int64.Max / people, "INVALID_BUDGET", "预算无效")
                                    }
                                    s.people = people
                                    s.budgetPerPersonFen = budget
                                case _ => ()
                            }
                            if (effective) {
                                invalidateRoom(db, s)
                            }
                    }
                    remember(db, s.id, visitor, requestId, signature, roomCode, s.expiresAt)
                    roomSnapshot(db, s, actor)
            }
        )
    }
    public func pruneExpired(): Unit {
        let now = clock.wallMillis()
        repository.transact(
            {
                db =>
                    pruneExpiredData(db, now)
                    Outcome.Ok(db)
            }
        ).unwrap()
    }
    func ownedCompanion(db: DatabaseSnapshot, s: Session, me: Participant, id: String): Participant {
        for (p in db.participants) {
            if (p.id == id && p.sessionId == s.id) {
                demand(p.source == "companion" && p.filledByParticipantId == Some(me.id), "FORBIDDEN",
                    "只能管理自己补充的同行人", status: 403)
                return p
            }
        }
        throw RoomFault("NOT_FOUND", "同行人记录不存在", status: 404)
    }
}

func sanitizeWishes(menu: MenuSnapshot, prefs: Preferences): Preferences {
    let copy = Preferences.fromJson(prefs.toJson())
    copy.wantedDishIds = copy.wantedDishIds.filter(
        {
            id =>
                for (d in menu.dishes) {
                    if (d.id == id && d.available) {
                        return evaluateMemberFit(d, copy, IngredientAssociations()).status != "conflict"
                    }
                }
                false
        }
    )
    copy.wantedSetMealIds = copy.wantedSetMealIds.filter(
        {
            id =>
                for (meal in menu.setMeals) {
                    if (meal.id == id) {
                        for (c in meal.components) {
                            for (d in menu.dishes) {
                                if (d.id == c.dishId && d.available &&
                                    evaluateMemberFit(d, copy, IngredientAssociations()).status != "conflict") {
                                    return true
                                }
                            }
                        }
                    }
                }
                false
        }
    )
    copy
}

func pruneExpiredData(db: DatabaseSnapshot, now: Int64): Unit {
    db.sessions = db.sessions.filter({s => s.expiresAt > now})
    let ids = db.sessions.map({s => s.id})
    db.participants = db.participants.filter({p => ids.contains(p.sessionId)})
    db.recommendations = db.recommendations.filter({r => ids.contains(r.sessionId)})
    db.jobs = db.jobs.filter({j => ids.contains(j.sessionId)})
    db.chatMessages = db.chatMessages.filter({m => ids.contains(m.sessionId)})
    db.dedupeRecords = db.dedupeRecords.filter({r => r.expiresAt > now})
}
