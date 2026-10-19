package huaiwei.platform

import std.fs.*
import std.io.*
import stdx.net.http.*

public func serveFrontend(root: String): HttpRequestHandler {
    FuncHandler(
        {
            ctx =>
                let path = ctx.request.url.path
                if (ctx.request.method != "GET" || path.contains("..") || path.contains("\\") || path.contains("%")) {
                    jsonError(ctx, 404, "NOT_FOUND", "页面不存在")
                    return
                }
                var file = root + "/index.html"
                var contentType = "text/html; charset=utf-8"
                if (path.startsWith("/assets/")) {
                    file = root + path
                    if (path.endsWith(".js")) {
                        contentType = "text/javascript; charset=utf-8"
                    } else if (path.endsWith(".css")) {
                        contentType = "text/css; charset=utf-8"
                    } else if (path.endsWith(".svg")) {
                        contentType = "image/svg+xml"
                    } else {
                        jsonError(ctx, 404, "NOT_FOUND", "资源不存在");
                        return
                    }
                } else if (path.startsWith("/menu-images/")) {
                    let filename = path[13..]
                    if (filename.isEmpty() || filename.contains("/")) {
                        jsonError(ctx, 404, "NOT_FOUND", "图片不存在")
                        return
                    }
                    file = root + path
                    if (path.endsWith(".jpg") || path.endsWith(".jpeg")) {
                        contentType = "image/jpeg"
                    } else if (path.endsWith(".png")) {
                        contentType = "image/png"
                    } else if (path.endsWith(".webp")) {
                        contentType = "image/webp"
                    } else if (path.endsWith(".gif")) {
                        contentType = "image/gif"
                    } else {
                        jsonError(ctx, 404, "NOT_FOUND", "图片类型不支持")
                        return
                    }
                } else if (path == "/admin" || path.startsWith("/admin/")) {
                    file = root + "/admin/index.html"
                } else if (!(path == "/" || path == "/account" || path.startsWith("/r/") || path.startsWith("/s/"))) {
                    jsonError(ctx, 404, "NOT_FOUND", "页面不存在");
                    return
                }
                try (input = File(file, Read)) {
                    ctx
                        .responseBuilder
                        .status(200)
                        .header("content-type", contentType)
                        .header("x-content-type-options", "nosniff")
                        .header("cache-control", if (contentType.startsWith("text/html")) {
                            "no-cache"
                        } else {
                            "public, max-age=31536000, immutable"
                        })
                        .body(readToEnd(input))
                } catch (_: Exception) {
                    jsonError(ctx, 404, "NOT_FOUND", "前端尚未构建或资源不存在")
                }
        }
    )
}
