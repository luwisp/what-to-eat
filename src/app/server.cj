package huaiwei.app

import std.env.*
import std.convert.*
import huaiwei.platform.*
import huaiwei.model.*
import huaiwei.store.*
import huaiwei.room.*
import huaiwei.agent.*
import huaiwei.auth.*
import huaiwei.catalog.*
import stdx.net.http.*
import stdx.encoding.json.*

public func serverConfigFromEnvironment(): ServerConfig {
    let host = getVariable("HUAIWEI_HOST") ?? "127.0.0.1"
    let port = UInt16.parse(getVariable("HUAIWEI_PORT") ?? "8080")
    let probes = (getVariable("HUAIWEI_ENABLE_PROBES") ?? "false") == "true"
    return ServerConfig(host, port, probes)
}

public func startServer(config: ServerConfig): Unit {
    let database = getVariable("HUAIWEI_DB_PATH") ?? "data/runtime/huaiwei.sqlite"
    let repository = SqliteRepository(database)
    let origin = getVariable("HUAIWEI_PUBLIC_BASE_URL") ?? "http://localhost:${config.port}"
    let auth = AuthService(repository, publicOrigin: origin)
    auth.pruneExpired().unwrap()
    let defaults = DefaultSettingsService(repository)
    let server = createDiningServer(config, repository, auth, origin, {router, committed =>
        registerAuthRoutes(router, auth, defaults)
        registerCatalogRoutes(router, repository, auth, origin, committed)
    })
    println("Huaiwei listening on ${config.host}:${config.port}")
    server.serve()
}

// Composition entry for the teammate's real repository and identity modules.
// Route registration happens once before serving; no demo storage is substituted.
public func createDiningServer(config: ServerConfig, repository: Repository, identities: IdentityResolver,
    publicOrigin: String, registerBackend: (HttpRouter, (String, Int64) -> Unit) -> Unit, enableModel!: Bool = true): Server {
    let rooms = RoomService(repository, SystemClock())
    rooms.pruneExpired()
    let coordinator = RecommendationCoordinator(rooms)
    coordinator.recoverInterruptedJobs()
    let model = modelConfigFromEnvironment()
    let client: ?LLMClient = if (enableModel && model.enabled()) {
        Some(HttpLLMClient(model))
    } else {
        None
    }
    let transport = DiningTransport(rooms, coordinator, identities, publicOrigin,
        assistant: DiningAssistant(client: client), interpreter: PreferenceInterpreter(client: client))
    return createHttpServer(
        config,
        configure: {
            router =>
                router.on("GET", "/api/capabilities", {ctx, _ =>
                    let o = JsonObject(); o.put("aiEnabled", JsonBool(client.isSome())); jsonResponse(ctx, 200, o)
                })
                registerBackend(router, {restaurantId, version => transport.onMenuCommitted(restaurantId, version)})
                transport.register(router)
                router.pages(serveFrontend("web"))
        }
    )
}
