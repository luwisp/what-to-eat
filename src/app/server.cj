package huaiwei.app

import std.env.*
import std.convert.*
import huaiwei.platform.*

public func serverConfigFromEnvironment(): ServerConfig {
    let host = getVariable("HUAIWEI_HOST") ?? "127.0.0.1"
    let port = UInt16.parse(getVariable("HUAIWEI_PORT") ?? "8080")
    let probes = (getVariable("HUAIWEI_ENABLE_PROBES") ?? "false") == "true"
    return ServerConfig(host, port, probes)
}

public func startServer(config: ServerConfig): Unit {
    let server = createHttpServer(config)
    println("Huaiwei listening on ${config.host}:${config.port}")
    server.serve()
}
