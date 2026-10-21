// Integration-only executable. These adapters never enter src/ or main.
import huaiwei.model.*
import huaiwei.app.*
import huaiwei.platform.*
import huaiwei.store.*
import huaiwei.room.*
import std.env.*
import std.convert.*
import std.sync.*
import stdx.net.http.*

class FixtureRepository <: Repository {
    let lock = Mutex()
    var data = DatabaseSnapshot(restaurants: [Restaurant(id: "r", restaurantCode: "TEST", name: "测试餐馆")],
        menuVersions: [MenuVersion(restaurantId: "r", menuVersion: 1)],
        dishes: [Dish(id: "a", restaurantId: "r", name: "青椒土豆", description: "青椒清香，土豆爽脆。",
            ingredients: ["青椒", "土豆"], priceFen: 1200),
            Dish(id: "b", restaurantId: "r", name: "清炒白菜", description: "清爽家常小炒。", ingredients: ["白菜"], priceFen: 1000),
            Dish(id: "u", restaurantId: "r", name: "今日小炒", ingredients: ["unknown"], priceFen: 1800)])
    public func read(): DatabaseSnapshot {
        synchronized(lock) {
            DatabaseSnapshot.fromJson(data.toJson())
        }
    }
    public func transact(change: (DatabaseSnapshot) -> Outcome<DatabaseSnapshot>): Outcome<Unit> {
        synchronized(lock) {
            match (change(DatabaseSnapshot.fromJson(data.toJson()))) {
                case Ok(next) =>
                    data = DatabaseSnapshot.fromJson(next.toJson())
                    Outcome.Ok(())
                case Err(e) => Outcome.Err(e)
            }
        }
    }
}

class FixtureIdentity <: IdentityResolver {
    public func resolve(cookies: String): Actor {
        for (cookie in cookies.split(";")) {
            let part = cookie.trimAscii()
            if (part.startsWith("test_visitor=")) {
                return Actor(visitorId: Some(part[13..]))
            }
        }
        Actor()
    }
    public func ensureVisitor(cookies: String): Outcome<VisitorSession> {
        let actor = resolve(cookies)
        if (actor.visitorId.isSome()) {
            return Outcome.Ok(VisitorSession(actor: actor))
        }
        let id = newId()
        Outcome.Ok(
            VisitorSession(actor: Actor(visitorId: Some(id)),
                setCookie: Some("test_visitor=${id}; Path=/; HttpOnly; SameSite=Lax")))
    }
}

main(): Int64 {
    let port = UInt16.parse(getVariable("HUAIWEI_PORT") ?? "8089")
    let repo = FixtureRepository()
    let identity = FixtureIdentity()
    let origin = getVariable("HUAIWEI_PUBLIC_BASE_URL") ?? "http://127.0.0.1:${port}"
    let server = createDiningServer(
        ServerConfig("127.0.0.1", port, false),
        repo,
        identity,
        origin,
        {
            router, onMenuCommitted =>
                router.on(
                    "POST",
                    "/api/visitor/session",
                    {
                        ctx, _ =>
                            let v = identity.ensureVisitor(ctx.request.headers.getFirst("cookie") ?? "").unwrap()
                            if (let Some(c) <- v.setCookie) {
                                ctx.responseBuilder.header("set-cookie", c)
                            }
                            ctx.responseBuilder.status(204)
                    }
                )
                router.on(
                    "GET",
                    "/api/restaurants/:restaurantCode/menu",
                    {
                        ctx, params =>
                            if (params["restaurantCode"] != "TEST") {
                                jsonError(ctx, 404, "NOT_FOUND", "餐馆不存在");
                                return
                            }
                            let db = repo.read()
                            jsonResponse(ctx, 200, roomMenu(db, Session(restaurantId: "r")).toJson())
                    }
                )
                router.on(
                    "POST",
                    "/__test/menu-change",
                    {
                        ctx, _ =>
                            repo.transact(
                                {
                                    db =>
                                    db.menuVersions[0].menuVersion++;
                                    db.dishes[0].ingredients = ["土豆", "unknown"]
                                    Outcome.Ok(db)
                                }
                            )
                            onMenuCommitted("r", repo.read().menuVersions[0].menuVersion)
                            ctx.responseBuilder.status(204)
                    }
                )
        },
        enableModel: false
    )
    server.serve()
    return 0
}
