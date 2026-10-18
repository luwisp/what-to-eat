package huaiwei.platform

import std.collection.*
import stdx.net.http.*
import stdx.log.*

public class ServerConfig {
    public let host: String
    public let port: UInt16
    public let enableProbes: Bool

    public init(host: String, port: UInt16, enableProbes: Bool) {
        this.host = host
        this.port = port
        this.enableProbes = enableProbes
    }
}

// Application-owned routing boundary. Module routes are registered before serving.
public class HttpRouter <: HttpRequestDistributor {
    let routes = HashMap<String, HttpRequestHandler>()

    public func register(path: String, handler: HttpRequestHandler): Unit {
        if (routes.contains(path)) {
            throw IllegalArgumentException("Duplicate route: ${path}")
        }
        routes.add(path, handler)
    }

    public func distribute(path: String): HttpRequestHandler {
        return routes.get(path) ?? FuncHandler({ctx =>
            ctx.responseBuilder.status(404)
                .header("content-type", "application/json; charset=utf-8")
                .body("{\"error\":{\"code\":\"NOT_FOUND\",\"message\":\"Route not found\"}}")
        })
    }
}

public func createHttpServer(config: ServerConfig): Server {
    let router = HttpRouter()
    router.register("/health", FuncHandler({ctx =>
        ctx.responseBuilder.status(200)
            .header("content-type", "application/json; charset=utf-8")
            .body("{\"status\":\"ok\",\"sdk\":\"1.2.0\"}")
    }))
    if (config.enableProbes) {
        router.register("/__probe/ws", FuncHandler(echoWebSocket))
    }
    let server = ServerBuilder().addr(config.host).port(config.port).distributor(router).build()
    server.logger.level = LogLevel.OFF
    return server
}

func echoWebSocket(ctx: HttpContext): Unit {
    let socket = WebSocket.upgradeFromServer(ctx)
    try {
        while (true) {
            let frame = socket.read()
            match (frame.frameType) {
                case TextWebFrame | BinaryWebFrame => socket.write(frame.frameType, frame.payload)
                case PingWebFrame => socket.writePongFrame(frame.payload)
                case CloseWebFrame =>
                    socket.write(CloseWebFrame, frame.payload)
                    return
                case _ => ()
            }
        }
    } finally {
        socket.closeConn()
    }
}
