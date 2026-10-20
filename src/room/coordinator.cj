package huaiwei.room

import huaiwei.model.*
import huaiwei.agent.*

class JobCell {
    public var job: ?RecommendationJob = None;
    public var snapshot: ?RoomSnapshot = None
}

public class RecommendationCoordinator {
    public let rooms: RoomService
    public init(rooms: RoomService) {
        this.rooms = rooms
    }
    public func request(actor: Actor, code: String, requestId: String, adjustment: ?RuleAdjustment,
        text!: ?String = None): Outcome<RecommendationJob> {
        let result = JobCell()
        let commit = rooms.repository.transact({
            db => try {
                let s = roomByCode(db, code, rooms.clock.wallMillis())
                let me = roomMember(db, s, actor)
                demand(!requestId.isEmpty() && requestId.size <= 128, "INVALID_REQUEST_ID", "requestId无效")
                demand(s.state != "closed", "ROOM_CLOSED", "请先重开", status: 409)
                demand(db.participants.any({p => p.sessionId == s.id && p.submitted}), "NO_SUBMISSIONS",
                    "至少一人提交后再推荐")
                let latestVersion = roomMenu(db, s).menuVersion
                if (latestVersion > s.menuVersion) {
                    s.menuVersion = latestVersion
                    invalidateRoom(db, s)
                }
                let operation: ?String = match (adjustment) {
                    case Some(_) => Some("addSoup");
                    case None => None
                }
                for (j in db.jobs) {
                    if (j.sessionId == s.id && j.requesterId == me.id && j.requestId == requestId) {
                        demand(j.adjustment == operation && j.text == text, "REQUEST_ID_REUSED",
                            "同一requestId不能用于不同操作", status: 409)
                        result.job = Some(RecommendationJob.fromJson(j.toJson()))
                        return Outcome.Ok(db)
                    }
                }
                for (j in db.jobs) {
                    if (j.sessionId == s.id && j.status == "inProgress") {
                        result.job = Some(RecommendationJob.fromJson(j.toJson()))
                        return Outcome.Ok(db)
                    }
                }
                if (let Some(message) <- text) {
                    demand(!message.trimAscii().isEmpty() && message.toRuneArray().size <= 200, "INVALID_NOTE",
                        "对话须为1至200字")
                    demand(!s.recommendationInvalid && db
                        .recommendations
                        .any({r => r.sessionId == s.id}), "CHAT_DISABLED", "请先生成有效方案再调整")
                }
                let job = RecommendationJob(id: newId(), sessionId: s.id, requesterId: me.id, requestId: requestId,
                    roomVersion: s.stateVersion, menuVersion: roomMenu(db, s).menuVersion,
                    startedAt: rooms.clock.wallMillis(), adjustment: operation, text: text)
                db.jobs = db.jobs.concat([job])
                if (let Some(message) <- text) {
                    db.chatMessages = db
                        .chatMessages
                        .concat(
                            [ChatMessage(id: newId(), sessionId: s.id, sender: me.id, role: "user", content: message,
                                createdAt: rooms.clock.wallMillis())])
                }
                result.job = Some(RecommendationJob.fromJson(job.toJson()))
                Outcome.Ok(db)
            } catch (e: RoomFault) {
                Outcome.Err(e.error)
            }
        })
        match (commit) {
            case Err(e) => Outcome.Err(e);
            case Ok(_) => Outcome.Ok(result.job.getOrThrow())
        }
    }
    public func inputFor(db: DatabaseSnapshot, job: RecommendationJob): RuleInput {
        for (s in db.sessions) {
            if (s.id == job.sessionId) {
                demand(
                    s.expiresAt > rooms.clock.wallMillis() && s.state != "closed" && s.stateVersion == job.roomVersion &&
                        roomMenu(db, s).menuVersion == job.menuVersion, "STALE_JOB", "条件已变化，旧任务结果已丢弃",
                    status: 409)
                var active = false
                for (j in db.jobs) {
                    if (j.id == job.id && j.status == "inProgress") {
                        active = true
                    }
                }
                demand(active, "STALE_JOB", "任务已结束或中断", status: 409)
                var base: Array<RecommendationItem> = []
                if (job.adjustment.isSome()) {
                    demand(!s.recommendationInvalid, "INVALID_RESULT", "请先重新推荐", status: 409)
                    for (r in db.recommendations) {
                        if (r.sessionId == s.id && r.menuVersion == job.menuVersion && r.roomVersion == job.roomVersion) {
                            base = r.draft.items
                        }
                    }
                    demand(!base.isEmpty(), "INVALID_RESULT", "没有可调整方案", status: 409)
                }
                return RuleInput(menu: roomMenu(db, s), members: db.participants.filter({p => p.sessionId == s.id}),
                    people: s.people, budgetPerPersonFen: s.budgetPerPersonFen, baseItems: base,
                    adjustment: job.adjustment)
            }
        }
        throw RoomFault("NOT_FOUND", "聚餐局不存在", status: 404)
    }
    public func calculate(job: RecommendationJob): Outcome<RecommendationDraft> {
        try {
            recommendMeal(inputFor(rooms.repository.read(), job))
        } catch (e: RoomFault) {
            Outcome.Err(e.error)
        }
    }
    public func commitResult(job: RecommendationJob, draft: RecommendationDraft, mode: String, explanation!: String = ""): Outcome<RoomSnapshot> {
        let result = JobCell()
        let commit = rooms.repository.transact({
            db => try {
                let input = inputFor(db, job)
                demand(validateAssociations(input.menu, draft.associations), "INVALID_ASSOCIATIONS", "食材关联无效")
                input.associations = draft.associations
                let validated = checkMealRecommendation(input, draft.items)
                if (let Err(e) <- validated) {
                    return Outcome.Err(e)
                }
                let s = db.sessions.filter({s => s.id == job.sessionId})[0]
                let members = input.members
                let r = Recommendation(id: newId(), sessionId: s.id, roomVersion: s.stateVersion,
                    menuVersion: input.menu.menuVersion, mode: if (mode == "ai") {
                        "ai"
                    } else {
                        "rules"
                    }, draft: validated.unwrap(), createdAt: rooms.clock.wallMillis(),
                    canConfirm: members.size >= s.people && members.all({p => p.submitted}) &&
                        validated.unwrap().uncoveredIds.isEmpty() && (input.menu.mealMetadata.isEmpty() || validated.unwrap().mealStatus == "complete"))
                db.recommendations = db.recommendations.filter({old => old.sessionId != s.id}).concat([r])
                for (j in db.jobs) {
                    if (j.id == job.id) {
                        j.status = "completed"
                    }
                }
                if (!explanation.isEmpty()) {
                    let history = db.chatMessages.filter({m => m.sessionId == s.id})
                    let keep = if (history.size > 19) {
                        history[history.size - 19..]
                    } else {
                        history
                    }
                    db.chatMessages = db
                        .chatMessages
                        .filter({m => m.sessionId != s.id})
                        .concat(keep)
                        .concat(
                            [ChatMessage(id: newId(), sessionId: s.id, sender: "agent", role: "agent",
                                content: explanation, createdAt: rooms.clock.wallMillis())])
                }
                s.state = "recommended"
                s.recommendationInvalid = false
                s.menuVersion = input.menu.menuVersion
                let requester = db.participants.filter({p => p.id == job.requesterId})[0]
                result.snapshot = Some(
                    roomSnapshot(db, s, Actor(visitorId: requester.visitorId, userId: requester.userId)))
                Outcome.Ok(db)
            } catch (e: RoomFault) {
                Outcome.Err(e.error)
            }
        })
        if (let Err(e) <- commit) {
            release(job.id, "failed");
            return Outcome.Err(e)
        }
        return Outcome.Ok(result.snapshot.getOrThrow())
    }
    public func release(jobId: String, status: String): Unit {
        rooms.repository.transact(
            {
                db =>
                    for (j in db.jobs) {
                        if (j.id == jobId && j.status == "inProgress") {
                            j.status = status
                        }
                    }
                    Outcome.Ok(db)
            }
        ).unwrap()
    }
    public func invalidateRestaurantRooms(restaurantId: String, menuVersion: Int64): Unit {
        rooms.repository.transact(
            {
                db =>
                    for (s in db.sessions) {
                        if (s.restaurantId == restaurantId) {
                            let actual = roomMenu(db, s).menuVersion
                            if (actual > s.menuVersion && actual >= menuVersion) {
                                s.menuVersion = actual
                                invalidateRoom(db, s)
                            }
                        }
                    }
                    Outcome.Ok(db)
            }
        ).unwrap()
    }
    public func recoverInterruptedJobs(): Unit {
        rooms.repository.transact(
            {
                db =>
                    for (j in db.jobs) {
                        if (j.status == "inProgress") {
                            j.status = "interrupted"
                        }
                    }
                    Outcome.Ok(db)
            }
        ).unwrap()
    }
}
