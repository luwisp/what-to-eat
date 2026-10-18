package huaiwei.app

import std.env.*
import std.convert.*
import huaiwei.platform.*
import huaiwei.model.*
import huaiwei.store.*
import huaiwei.room.*
import huaiwei.agent.*
import stdx.net.http.*

public func serverConfigFromEnvironment(): ServerConfig {
    let host = getVariable("HUAIWEI_HOST") ?? "127.0.0.1"
    let port = UInt16.parse(getVariable("HUAIWEI_PORT") ?? "8080")
    let probes = (getVariable("HUAIWEI_ENABLE_PROBES") ?? "false") == "true"
    return ServerConfig(host, port, probes)
}

public func startServer(config: ServerConfig): Unit {
    let server = createHttpServer(config, configure: {router => router.pages(serveFrontend("web"))})
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
                registerBackend(router, {restaurantId, version => transport.onMenuCommitted(restaurantId, version)})
                transport.register(router)
                router.pages(serveFrontend("web"))
        }
    )
}
