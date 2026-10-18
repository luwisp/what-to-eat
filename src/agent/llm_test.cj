package huaiwei.agent

import huaiwei.platform.*
import stdx.net.http.*
import std.sync.*
import std.time.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class LLMHttpTests {
    @TestCase
    func deadlineCancelsActualSlowHTTPAndAuthenticationIsTyped() {
        let router = HttpRouter()
        router.register(
            "/slow/chat/completions",
            FuncHandler(
                {
                    ctx =>
                        sleep(250 * Duration.millisecond)
                        ctx.responseBuilder.body("{\"choices\":[{\"message\":{\"content\":\"{}\"}}]}")
                }
            )
        )
        router.register("/auth/chat/completions",
            FuncHandler({ctx => ctx.responseBuilder.status(401).body("sensitive upstream response")}))
        let ready = AtomicBool(false)
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
        try {
            for (_ in 0..100) {
                if (ready.load()) {
                    break
                };
                sleep(Duration.millisecond)
            }
            @Expect(ready.load(), true)
            let clock = SystemClock()
            let started = clock.monotonicMillis()
            let client = HttpLLMClient(ModelConfig("test-key", "http://127.0.0.1:${server.port}/slow", "test-model"))
            let result = client.complete([modelMessage("user", "test")], [], Deadline(clock, 30))
            @Expect(result.isOk(), false)
            @Expect(clock.monotonicMillis() - started < 200, true)
            let auth = HttpLLMClient(ModelConfig("test-key", "http://127.0.0.1:${server.port}/auth", "test-model"))
                .complete([modelMessage("user", "test")], [], Deadline(clock, 1000))
            match (auth) {
                case Err(e) => @Expect(e.code, "MODEL_AUTH")
                case _ => @Expect(false, true)
            }
        } finally {
            server.close();
            worker.get()
        }
    }
}
