package juxiaobao.auth

import juxiaobao.model.*
import juxiaobao.platform.*
import stdx.encoding.json.*
import stdx.net.http.*

class AuthInputFault <: Exception {
    init() {
        super("Invalid request")
    }
}

func authBody(ctx: HttpContext): JsonObject {
    try {
        readJsonBody(ctx)
    } catch (_: Exception) {
        throw AuthInputFault()
    }
}

func credentials(body: JsonObject): (String, String) {
    try {
        rejectUnknown(body, ["login", "password"])
        (body["login"].asString().getValue(), body["password"].asString().getValue())
    } catch (_: Exception) {
        throw AuthInputFault()
    }
}

func rejectUnknown(obj: JsonObject, allowed: Array<String>): Unit {
    for ((key, _) in obj.getFields()) {
        if (!allowed.any({v => v == key})) {
            throw AuthInputFault()
        }
    }
}

func checkOrigin(ctx: HttpContext, origin: String): Bool {
    if (let Some(value) <- ctx.request.headers.getFirst("origin")) {
        return value == origin
    }
    ctx.request.headers.getFirst("sec-fetch-site") != Some("cross-site")
}

func routeGuard(ctx: HttpContext, auth: AuthService, mutate: Bool, action: () -> Unit): Unit {
    if (mutate && !checkOrigin(ctx, auth.publicOrigin)) {
        jsonError(ctx, 403, "INVALID_ORIGIN", "请求来源无效")
        return
    }
    try {
        action()
    } catch (_: AuthInputFault) {
        jsonError(ctx, 400, "INVALID_INPUT", "请求格式无效")
    } catch (_: Exception) {
        jsonError(ctx, 500, "INTERNAL_ERROR", "服务暂不可用")
    }
}

public func registerAuthRoutes(router: HttpRouter, auth: AuthService, defaults: DefaultSettingsService): Unit {
    router.on("POST", "/api/visitor/session", {
        ctx, _ => routeGuard(ctx, auth, true, {
            => match (auth.ensureVisitor(ctx.request.headers.getFirst("cookie") ?? "")) {
                case Ok(value) =>
                    if (let Some(cookie) <- value.setCookie) {
                        ctx.responseBuilder.header("set-cookie", cookie)
                    }
                    ctx.responseBuilder.status(204)
                case Err(e) => jsonError(ctx, e.status, e.code, e.message)
            }
        })
    })
    for (kind in [AccountKind.User, AccountKind.Merchant]) {
        let accountKind = kind
        let prefix = "/api/" + accountKind.toWire()
        router.on("POST", prefix + "/register", {
            ctx, _ => routeGuard(
                ctx,
                auth,
                true,
                {
                    =>
                        let (login, password) = credentials(authBody(ctx))
                        match (auth.register(accountKind, login, password)) {
                            case Ok(value) => jsonResponse(ctx, 201, value.toJson())
                            case Err(e) => jsonError(ctx, e.status, e.code, e.message)
                        }
                }
            )
        })
        router.on("POST", prefix + "/login", {
            ctx, _ => routeGuard(
                ctx,
                auth,
                true,
                {
                    =>
                        let (login, password) = credentials(authBody(ctx))
                        match (auth.login(accountKind, login, password,
                            cookies: ctx.request.headers.getFirst("cookie") ?? "")) {
                            case Ok(value) =>
                                ctx.responseBuilder.header("set-cookie", value.setCookie)
                                jsonResponse(ctx, 200, value.account.toJson())
                            case Err(e) => jsonError(ctx, e.status, e.code, e.message)
                        }
                }
            )
        })
        router.on("POST", prefix + "/logout", {
            ctx, _ => routeGuard(ctx, auth, true, {
                => match (auth.logout(accountKind, ctx.request.headers.getFirst("cookie") ?? "")) {
                    case Ok(_) =>
                        ctx.responseBuilder.header("set-cookie", auth.clearCookie(accountKind))
                        ctx.responseBuilder.status(204)
                    case Err(e) => jsonError(ctx, e.status, e.code, e.message)
                }
            })
        })
        router.on("GET", prefix + "/me", {
            ctx, _ => routeGuard(ctx, auth, false, {
                => match (auth.me(accountKind, ctx.request.headers.getFirst("cookie") ?? "")) {
                    case Ok(value) => jsonResponse(ctx, 200, value.toJson())
                    case Err(e) => jsonError(ctx, e.status, e.code, e.message)
                }
            })
        })
    }
    router.on("PATCH", "/api/user/profile", {
        ctx, _ => routeGuard(
            ctx,
            auth,
            true,
            {
                =>
                    let body = authBody(ctx)
                    rejectUnknown(body, ["nickname"])
                    let name = try {
                        body["nickname"].asString().getValue()
                    } catch (_: Exception) {
                        throw AuthInputFault()
                    }
                    match (auth.updateProfile(ctx.request.headers.getFirst("cookie") ?? "", name)) {
                        case Ok(value) => jsonResponse(ctx, 200, value.toJson());
                        case Err(e) => jsonError(ctx, e.status, e.code, e.message)
                    }
            }
        )
    })
    router.on("GET", "/api/user/default-settings", {
        ctx, _ => routeGuard(ctx, auth, false, {
            => match (defaults.get(auth.resolve(ctx.request.headers.getFirst("cookie") ?? ""))) {
                case Ok(value) => jsonResponse(ctx, 200, value.toJson())
                case Err(e) => jsonError(ctx, e.status, e.code, e.message)
            }
        })
    })
    router.on("PUT", "/api/user/default-settings", {
        ctx, _ => routeGuard(
            ctx,
            auth,
            true,
            {
                =>
                    let actor = auth.resolve(ctx.request.headers.getFirst("cookie") ?? "")
                    if (actor.userId.isNone()) {
                        jsonError(ctx, 401, "UNAUTHENTICATED", "请先登录");
                        return
                    }
                    let settings = parseDefaults(authBody(ctx))
                    match (defaults.put(actor, settings)) {
                        case Ok(value) => jsonResponse(ctx, 200, value.toJson())
                        case Err(e) => jsonError(ctx, e.status, e.code, e.message)
                    }
            }
        )
    })
}

func parseDefaults(body: JsonObject): UserDefaultSettings {
    try {
        rejectUnknown(body, ["allergens", "avoidFoods", "dietMode", "maxSpiceLevel", "tastePreferences", "appetite"])
        UserDefaultSettings(appetite: if (body.containsKey("appetite")) {
            body["appetite"].asString().getValue()
        } else {
            "normal"
        }, allergens: body["allergens"].asArray().getItems().toArray().map({v => v.asString().getValue()}),
            avoidFoods: body["avoidFoods"].asArray().getItems().toArray().map({v => v.asString().getValue()}),
            dietMode: body["dietMode"].asString().getValue(), maxSpiceLevel: match (body["maxSpiceLevel"]) {
                case _: JsonNull => None;
                case _ => Some(body["maxSpiceLevel"].asInt().getValue())
            },
            tastePreferences: body["tastePreferences"]
                .asArray()
                .getItems()
                .toArray()
                .map({v => v.asString().getValue()}))
    } catch (_: Exception) {
        throw AuthInputFault()
    }
}
