package juxiaobao.room

import juxiaobao.model.*
import juxiaobao.platform.*
import juxiaobao.agent.*
import std.collection.*
import std.sync.*
import stdx.net.http.*
import stdx.encoding.json.*

public class RoomSubscriber {
    public let id: String
    public let actor: Actor
    public var code: String = ""
    let socket: WebSocket
    let writeLock = Mutex()
    public init(actor: Actor, socket: WebSocket) {
        id = newId()
        this.actor = actor
        this.socket = socket
    }
    public func send(kind: String, value: JsonValue, requestId!: String = ""): Unit {
        let message = JsonObject()
        message.put("type", JsonString(kind));
        message.put("payload", value)
        if (!requestId.isEmpty()) {
            message.put("requestId", JsonString(requestId))
        }
        synchronized(writeLock) {
            socket.write(TextWebFrame, message.toString().toArray())
        }
    }
}

public class DiningTransport {
    public let rooms: RoomService
    public let coordinator: RecommendationCoordinator
    let assistant: DiningAssistant
    let interpreter: PreferenceInterpreter
    let identities: IdentityResolver
    let origin: String
    let lock = Mutex()
    let listeners = HashMap<String, RoomSubscriber>()
    let workers = HashSet<String>()
    public init(rooms: RoomService, coordinator: RecommendationCoordinator, identities: IdentityResolver,
        publicOrigin: String, assistant!: DiningAssistant = DiningAssistant(),
        interpreter!: PreferenceInterpreter = PreferenceInterpreter()) {
        this.rooms = rooms
        this.coordinator = coordinator
        this.identities = identities
        this.origin = publicOrigin
        this.assistant = assistant
        this.interpreter = interpreter
    }
    public func broadcast(code: String, requestId!: String = "", sender!: String = ""): Unit {
        let targets = synchronized(lock) {
            listeners.values().toArray()
        }
        for (target in targets) {
            if (target.code != code) {
                continue
            }
            try {
                match (rooms.snapshot(target.actor, code)) {
                    case Ok(state) => target.send("room_state", state.toJson(),
                        requestId: if (sender == target.id) {
                            requestId
                        } else {
                            ""
                        })
                    case Err(e) => sendError(target, e, "")
                }
            } catch (_: Exception) {
                synchronized(lock) {
                    listeners.remove(target.id)
                }
            }
        }
    }
    public func onMenuCommitted(restaurantId: String, menuVersion: Int64): Unit {
        coordinator.invalidateRestaurantRooms(restaurantId, menuVersion)
        for (s in rooms.repository.read().sessions) {
            if (s.restaurantId == restaurantId) {
                broadcast(s.roomCode)
            }
        }
    }
    func checkOrigin(ctx: HttpContext): Unit {
        if (let Some(value) <- ctx.request.headers.getFirst("origin")) {
            demand(value == origin, "INVALID_ORIGIN", "请求来源无效", status: 403)
        } else {
            // Non-browser HTTP clients may omit Origin. WS connections must send
            // it because cookies authorize commands after upgrade.
            demand(ctx.request.headers.getFirst("sec-fetch-site") != Some("cross-site"), "INVALID_ORIGIN",
                "请求来源无效", status: 403)
        }
    }
    func visitor(ctx: HttpContext): Actor {
        let value = identities.ensureVisitor(ctx.request.headers.getFirst("cookie") ?? "")
        if (let Err(e) <- value) {
            throw RoomFault(e.code, e.message, status: e.status)
        }
        let session = value.unwrap()
        if (let Some(cookie) <- session.setCookie) {
            ctx.responseBuilder.header("set-cookie", cookie)
        }
        session.actor
    }
    public func register(router: HttpRouter): Unit {
        router.on("GET", "/api/entry/:code", {ctx, params =>
            match (rooms.resolveEntry(params["code"])) {
                case Ok(value) => jsonResponse(ctx, 200, value);
                case Err(e) => jsonError(ctx, e.status, e.code, e.message)
            }
        })
        router.on("POST", "/api/preferences/interpret", {
            ctx, _ => try {
                checkOrigin(ctx)
                let obj = readJsonBody(ctx)
                let prefs = Preferences.fromJson(obj["prefs"].asObject())
                checkPreferences(prefs)
                let result = interpreter.interpret(prefs, obj["note"].asString().getValue(), Deadline(rooms.clock, 29500))
                match (result) {
                    case Ok(value) => jsonResponse(ctx, 200, value);
                    case Err(e) => jsonError(ctx, e.status, e.code, e.message)
                }
            } catch (e: RoomFault) {
                jsonError(ctx, e.error.status, e.error.code, e.error.message)
            } catch (_: Exception) {
                jsonError(ctx, 400, "INVALID_INPUT", "请求格式无效")
            }
        })
        router.on("POST", "/api/sessions", {
            ctx, _ => try {
                checkOrigin(ctx)
                let actor = visitor(ctx)
                let obj = readJsonBody(ctx)
                let input = CreateSessionInput.fromJson(obj)
                respond(ctx, rooms.create(actor, input, obj["requestId"].asString().getValue()), 201)
            } catch (e: RoomFault) {
                jsonError(ctx, e.error.status, e.error.code, e.error.message)
            } catch (_: Exception) {
                jsonError(ctx, 400, "INVALID_INPUT", "请求格式无效")
            }
        })
        router.on(
            "GET",
            "/api/sessions/:roomCode",
            {
                ctx, params =>
                    let actor = identities.resolve(ctx.request.headers.getFirst("cookie") ?? "")
                    respond(ctx, rooms.snapshot(actor, params["roomCode"]), 200)
            }
        )
        router.register("/ws", FuncHandler({
            ctx => try {
                checkOrigin(ctx)
                demand(ctx.request.headers.getFirst("origin") == Some(origin), "INVALID_ORIGIN", "WebSocket请求来源无效",
                    status: 403)
                let actor = visitor(ctx)
                demand(actor.visitorId.isSome(), "VISITOR_REQUIRED", "访客会话无效", status: 401)
                socketLoop(RoomSubscriber(actor, WebSocket.upgradeFromServer(ctx)))
            } catch (e: RoomFault) {
                jsonError(ctx, e.error.status, e.error.code, e.error.message)
            }
        }))
    }
    func respond(ctx: HttpContext, result: Outcome<RoomSnapshot>, status: UInt16): Unit {
        match (result) {
            case Ok(state) => jsonResponse(ctx, status, state.toJson());
            case Err(e) => jsonError(ctx, e.status, e.code, e.message)
        }
    }
    func sendError(connection: RoomSubscriber, error: DomainError, requestId: String): Unit {
        let body = JsonObject();
        body.put("code", JsonString(error.code));
        body.put("message", JsonString(error.message))
        connection.send("error", body, requestId: requestId)
    }
    func socketLoop(connection: RoomSubscriber): Unit {
        synchronized(lock) {
            listeners[connection.id] = connection
        }
        var fragment: Array<UInt8> = []
        var continuing = false
        try {
            while (true) {
                let frame = connection.socket.read()
                match (frame.frameType) {
                    case PingWebFrame =>
                        connection.socket.writePongFrame(frame.payload);
                        continue
                    case PongWebFrame => continue
                    case CloseWebFrame =>
                        connection.socket.write(CloseWebFrame, frame.payload);
                        return
                    case TextWebFrame =>
                        demand(!continuing, "INVALID_FRAME", "帧顺序错误")
                        fragment = frame.payload
                    case ContinuationWebFrame =>
                        demand(continuing, "INVALID_FRAME", "帧顺序错误")
                        fragment = fragment.concat(frame.payload)
                    case _ => throw RoomFault("INVALID_FRAME", "仅支持文本消息")
                }
                demand(fragment.size <= 65536, "MESSAGE_TOO_LARGE", "消息过大")
                continuing = !frame.fin
                if (continuing) {
                    continue
                }
                var requestId = ""
                try {
                    let message = JsonValue.fromStr(String.fromUtf8(fragment)).asObject()
                    requestId = message["requestId"].asString().getValue()
                    demand(!requestId.isEmpty() && requestId.size <= 128, "INVALID_REQUEST_ID", "requestId无效")
                    dispatch(connection, message["type"].asString().getValue(), message["payload"].asObject(), requestId)
                } catch (e: RoomFault) {
                    sendError(connection, e.error, requestId)
                    if (!connection.code.isEmpty()) {
                        broadcast(connection.code)
                    }
                } catch (_: Exception) {
                    sendError(connection, DomainError("INVALID_INPUT", "消息格式无效"), requestId)
                }
                fragment = []
            }
        } catch (_: Exception) {
        // A disconnected or malformed client cannot end another connection.
        } finally {
            synchronized(lock) {
                listeners.remove(connection.id)
            };
            connection.socket.closeConn()
        }
    }
    func dispatch(connection: RoomSubscriber, kind: String, payload: JsonObject, requestId: String): Unit {
        if (kind == "join_room") {
            let code = payload["code"].asString().getValue()
            let result = rooms.join(connection.actor, code,
                nickname: if (let Some(v) <- payload.get("nickname")) {
                    Some(v.asString().getValue())
                } else {
                    None
                })
            if (let Err(e) <- result) {
                sendError(connection, e, requestId);
                return
            }
            connection.code = code
            broadcast(code, requestId: requestId, sender: connection.id)
            return
        }
        demand(!connection.code.isEmpty(), "NOT_A_MEMBER", "请先加入房间", status: 403)
        if (kind == "request_recommendation" || kind == "chat_message") {
            let adjustment: ?RuleAdjustment = if (payload.get("adjustment").isSome()) {
                Some(RuleAdjustment.AddSoup)
            } else {
                None
            }
            if (payload.get("adjustment").isSome()) {
                demand(payload["adjustment"].asString().getValue() == "addSoup", "INVALID_ADJUSTMENT", "快捷调整无效")
            }
            let text: ?String = if (kind == "chat_message") {
                Some(payload["text"].asString().getValue())
            } else {
                None
            }
            let job = coordinator.request(connection.actor, connection.code, requestId, adjustment, text: text)
            if (let Err(e) <- job) {
                sendError(connection, e, requestId);
                return
            }
            let work = job.unwrap()
            connection.send("recommendation_started", work.toJson(), requestId: requestId)
            if (work.status != "inProgress") {
                broadcast(connection.code);
                return
            }
            let begin = synchronized(lock) {
                if (workers.contains(work.id)) {
                    false
                } else {
                    workers.add(work.id);
                    true
                }
            }
            if (begin) {
                broadcast(connection.code)
                let code = connection.code
                spawn {
                    try {
                        let db = rooms.repository.read()
                        let input = coordinator.inputFor(db, work)
                        let deadline = Deadline(rooms.clock, 29500)
                        let result = if (let Some(message) <- work.text) {
                            let current = db.recommendations.filter({r => r.sessionId == work.sessionId})[0]
                            assistant.adjust(input, current, message,
                                db.chatMessages.filter({m => m.sessionId == work.sessionId}), deadline)
                        } else if (work.adjustment.isSome()) {
                            match (coordinator.calculate(work)) {
                                case Ok(draft) => Outcome<AssistantResult>.Ok(
                                    AssistantResult(draft, "rules", "已按这一桌的要求重新搭配，你看看这次合不合适。"));
                                case Err(e) => Outcome<AssistantResult>.Err(e)
                            }
                        } else {
                            assistant.recommend(input, deadline)
                        }
                        if (let Ok(value) <- result) {
                            let saved = if (value.changed) {
                                coordinator.commitResult(work, value.draft, value.mode, explanation: value.explanation)
                            } else { coordinator.commitMessage(work, value.explanation) }
                            if (let Err(e) <- saved) {
                                sendError(connection, e, "")
                            }
                        } else {
                            coordinator.release(work.id, "failed");
                            if (let Err(e) <- result) {
                                sendError(connection, e, "")
                            }
                        }
                    } catch (_: Exception) {
                        coordinator.release(work.id, "failed")
                    } finally {
                        synchronized(lock) {
                            workers.remove(work.id)
                        };
                        broadcast(code)
                    }
                }
            }
            return
        }
        let version = payload["expectedVersion"].asInt().getValue()
        let command: RoomCommand = match (kind) {
            case "update_preferences" => RoomCommand.UpdatePreferences(
                Preferences.fromJson(payload["prefs"].asObject()), payload["submit"].asBool().getValue())
            case "add_companion" => RoomCommand.AddCompanion(Preferences.fromJson(payload["prefs"].asObject()),
                optionalName(payload))
            case "update_companion" => RoomCommand.UpdateCompanion(payload["id"].asString().getValue(),
                Preferences.fromJson(payload["prefs"].asObject()), optionalName(payload))
            case "remove_companion" => RoomCommand.RemoveCompanion(payload["id"].asString().getValue())
            case "update_session" => RoomCommand.UpdateSession(payload["people"].asInt().getValue(),
                optionalBudget(payload))
            case "confirm_recommendation" => RoomCommand.Confirm(payload["id"].asString().getValue(),
                payload["version"].asInt().getValue())
            case "edit_recommendation" => RoomCommand.EditResult(parseProposedItems(payload["items"]))
            case "reopen_recommendation" => RoomCommand.Reopen
            case _ => throw RoomFault("UNKNOWN_COMMAND", "未知操作")
        }
        let result = rooms.apply(connection.actor, connection.code, command, version, requestId)
        if (let Err(e) <- result) {
            sendError(connection, e, requestId);
            broadcast(connection.code);
            return
        }
        broadcast(connection.code, requestId: requestId, sender: connection.id)
    }
}

func optionalName(obj: JsonObject): String {
    if (let Some(value) <- obj.get("nickname")) {
        return value.asString().getValue()
    }
    ""
}

func optionalBudget(obj: JsonObject): ?Int64 {
    match (obj["budgetPerPersonFen"]) {
        case _: JsonNull => None;
        case value => Some(value.asInt().getValue())
    }
}
