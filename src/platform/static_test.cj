package juxiaobao.platform

import std.fs.*
import std.io.*
import std.collection.*
import std.sync.*
import std.unittest.*
import std.unittest.testmacro.*
import stdx.net.http.*

@Test
class StaticImageTests {
    @TestCase
    func importedImagesAreServedAsImagesAndOtherFilesAreRejected() {
        let root = "target/menu-static-test-${SystemClock().wallMillis()}"
        Directory.create(root + "/menu-images", recursive: true)
        let image: Array<UInt8> = [137, 80, 78, 71]
        try (file = File.create(root + "/menu-images/example.png")) {
            file.write(image)
        }
        Directory.create(root + "/assets", recursive: true)
        for (name in ["home.png", "logo.png", "photo.jpg", "photo.jpeg", "photo.webp", "photo.gif"]) {
            try (file = File.create(root + "/assets/" + name)) { file.write(image) }
        }
        let ready = AtomicBool(false)
        let router = HttpRouter()
        router.pages(serveFrontend(root))
        let server = ServerBuilder()
            .addr("127.0.0.1")
            .port(0)
            .distributor(router)
            .afterBind({=> ready.store(true)})
            .build()
        let worker = spawn {
            try {
            server.serve()
        } catch (_: Exception) {
            ()
        }
        }
        let client = ClientBuilder().build()
        try {
            for (_ in 0..1000) {
                if (ready.load()) {
                    break
                };
                sleep(Duration.millisecond)
            }
            @Expect(ready.load(), true)
            let base = "http://127.0.0.1:${server.port}"
            let response = client.send(HttpRequestBuilder().url(base + "/menu-images/example.png").build())
            @Expect(response.status, 200)
            @Expect(response.headers.getFirst("content-type"), Some("image/png"))
            @Expect(readStaticBytes(response.body), image)
            for ((name, mime) in [("home.png", "image/png"), ("logo.png", "image/png"),
                ("photo.jpg", "image/jpeg"), ("photo.jpeg", "image/jpeg"),
                ("photo.webp", "image/webp"), ("photo.gif", "image/gif")]) {
                let asset = client.send(HttpRequestBuilder().url(base + "/assets/" + name).build())
                @Expect(asset.status, 200)
                @Expect(asset.headers.getFirst("content-type"), Some(mime))
                @Expect(readStaticBytes(asset.body), image)
            }
            for (path in ["/menu-images/missing.jpg", "/menu-images/file.html", "/menu-images/nested/a.png", "/assets/file.html", "/assets/missing.png"]) {
                let invalid = client.send(HttpRequestBuilder().url(base + path).build())
                @Expect(invalid.status, 404)
                readLimited(invalid.body)
            }
        } finally {
            client.close();
            server.close();
            worker.get()
            for (name in ["home.png", "logo.png", "photo.jpg", "photo.jpeg", "photo.webp", "photo.gif"]) {
                removeIfExists(root + "/assets/" + name)
            }
            removeIfExists(root + "/assets")
            removeIfExists(root + "/menu-images/example.png")
            removeIfExists(root + "/menu-images")
            removeIfExists(root)
        }
    }
}

func readStaticBytes(stream: InputStream): Array<UInt8> {
    let bytes = ArrayList<UInt8>()
    let buffer = Array<UInt8>(1024, repeat: 0)
    while (true) {
        let count = stream.read(buffer)
        if (count == 0) { break }
        bytes.add(all: buffer[0..count])
    }
    bytes.toArray()
}
