package huaiwei.platform

import std.collection.*
import stdx.net.http.*
import stdx.log.*
import stdx.encoding.json.*

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
    let moduleRoutes = ArrayList<ModuleRoute>()

    public func register(path: String, handler: HttpRequestHandler): Unit {
        if (routes.contains(path)) {
            throw IllegalArgumentException("Duplicate route: ${path}")
        }
        routes.add(path, handler)
    }

    public func distribute(path: String): HttpRequestHandler {
        return routes.get(path) ?? FuncHandler({ctx =>
            var matchedPath = false
            for (route in moduleRoutes) {
                if (let Some(params) <- matchRoutePath(route.path, path)) {
                    matchedPath = true
                    if (ctx.request.method == route.method) {
                        route.handler(ctx, params)
                        return
                    }
                }
            }
            jsonError(ctx, if (matchedPath) { 405 } else { 404 },
                if (matchedPath) { "METHOD_NOT_ALLOWED" } else { "NOT_FOUND" },
                if (matchedPath) { "Method not allowed" } else { "Route not found" })
        })
    }

    public func on(method: String, path: String, handler: (HttpContext, HashMap<String, String>) -> Unit): Unit {
        for (route in moduleRoutes) {
            if (route.method == method && route.path == path) { throw IllegalArgumentException("Duplicate route") }
        }
        moduleRoutes.add(ModuleRoute(method, path, handler))
    }
}

class ModuleRoute {
    let method: String
    let path: String
    let handler: (HttpContext, HashMap<String, String>) -> Unit
    init(method: String, path: String, handler: (HttpContext, HashMap<String, String>) -> Unit) {
        this.method = method
        this.path = path
        this.handler = handler
    }
}

public func matchRoutePath(pattern: String, path: String): ?HashMap<String, String> {
    let expected = pattern.split("/")
    let actual = path.split("/")
    if (expected.size != actual.size) { return None }
    let params = HashMap<String, String>()
    for (i in 0..expected.size) {
        if (expected[i].startsWith(":")) {
            if (actual[i].isEmpty()) { return None }
            params.add(expected[i][1..], actual[i])
        } else if (expected[i] != actual[i]) { return None }
    }
    return Some(params)
}

public func jsonError(ctx: HttpContext, status: UInt16, code: String, message: String): Unit {
    let error = JsonObject()
    error.put("code", JsonString(code))
    error.put("message", JsonString(message))
    let body = JsonObject()
    body.put("error", error)
    jsonResponse(ctx, status, body)
}

public func jsonResponse(ctx: HttpContext, status: UInt16, value: JsonValue): Unit {
    ctx.responseBuilder.status(status).header("content-type", "application/json; charset=utf-8").body(value.toString())
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
        for (method in ["GET", "POST"]) {
            router.on(method, "/__probe/items/:id", {ctx, params =>
                let value = JsonObject()
                value.put("id", JsonString(params["id"]))
                value.put("method", JsonString(ctx.request.method))
                jsonResponse(ctx, if (ctx.request.method == "GET") { 200 } else { 201 }, value)
            })
        }
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
