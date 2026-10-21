package juxiaobao.catalog

import juxiaobao.model.*
import juxiaobao.store.*
import juxiaobao.auth.*
import juxiaobao.platform.*
import juxiaobao.room.*
import std.fs.*
import stdx.encoding.base64.*
import stdx.encoding.json.*

// Uploaded bytes never supply a filename or path. Only common raster formats
// are accepted; originals live outside the rebuilt web directory.
public func registerImageUpload(router: HttpRouter, repository: Repository, auth: AuthService, origin: String,
    root: String): Unit {
    router.on("POST", "/api/merchant/images", {
        ctx, _ => try {
            demand(
                ctx.request.headers.getFirst("origin") == Some(origin) || (ctx
                    .request
                    .headers
                    .getFirst("origin")
                    .isNone() && ctx.request.headers.getFirst("sec-fetch-site") != Some("cross-site")), "INVALID_ORIGIN",
                "请求来源无效", status: 403)
            let actor = auth.resolve(ctx.request.headers.getFirst("cookie") ?? "")
            owner(repository.read(), actor)
            demand(!root.isEmpty(), "UPLOAD_DISABLED", "图片上传暂不可用", status: 503)
            let body = JsonValue.fromStr(readLimited(ctx.request.body, limit: 2900000)).asObject()
            let raw = body["data"].asString().getValue()
            demand(raw.size <= 2800000, "IMAGE_TOO_LARGE", "图片请压缩到2MB以内", status: 413)
            let bytes = fromBase64String(raw).getOrThrow()
            demand(bytes.size > 12 && bytes.size <= 2097152, "INVALID_IMAGE", "请选择2MB以内的JPG、PNG或WebP图片")
            let ext = imageExtension(bytes)
            demand(!ext.isEmpty(), "INVALID_IMAGE", "只支持JPG、PNG或WebP图片")
            Directory.create(root, recursive: true)
            let filename = newId() + "." + ext
            try (file = File.create(root + "/" + filename)) {
                file.write(bytes)
            }
            let response = JsonObject()
            response.put("imageUrl", JsonString("/uploads/menu/" + filename))
            jsonResponse(ctx, 201, response)
        } catch (e: RoomFault) {
            jsonError(ctx, e.error.status, e.error.code, e.error.message)
        } catch (_: Exception) {
            jsonError(ctx, 400, "INVALID_IMAGE", "图片未上传成功，请选择有效图片重试")
        }
    })
}

func imageExtension(bytes: Array<UInt8>): String {
    if (bytes.size < 12) {
        return ""
    }
    if (bytes[0..8] == [137u8, 80, 78, 71, 13, 10, 26, 10]) {
        return "png"
    }
    if (bytes[0] == 255 && bytes[1] == 216 && bytes[2] == 255) {
        return "jpg"
    }
    if (bytes[0..4] == [82u8, 73, 70, 70] && bytes[8..12] == [87u8, 69, 66, 80]) {
        return "webp"
    }
    ""
}
