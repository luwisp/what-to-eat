package huaiwei.auth

import huaiwei.model.*
import huaiwei.store.*
import huaiwei.platform.*
import std.sync.*
import stdx.net.http.*
import stdx.encoding.json.*
import std.unittest.*
import std.unittest.testmacro.*

// Contract fake only; production uses B1's shared durable repository.
class AuthTestRepository <: Repository {
    var data = DatabaseSnapshot()
    var failWrite = false
    let lock = Mutex()
    public func read(): DatabaseSnapshot {
        synchronized(lock) {
            DatabaseSnapshot.fromJson(data.toJson())
        }
    }
    public func transact(change: (DatabaseSnapshot) -> Outcome<DatabaseSnapshot>): Outcome<Unit> {
        synchronized(lock) {
            match (change(DatabaseSnapshot.fromJson(data.toJson()))) {
                case Ok(next) =>
                    if (failWrite) {
                        return Outcome<Unit>.Err(DomainError("STORE_FAILED", "写入失败", status: 500))
                    }
                    data = DatabaseSnapshot.fromJson(next.toJson())
                    Outcome<Unit>.Ok(())
                case Err(e) => Outcome<Unit>.Err(e)
            }
        }
    }
}

class AuthTestClock <: Clock {
    public var now: Int64 = 100000
    public func wallMillis(): Int64 {
        now
    }
    public func monotonicMillis(): Int64 {
        now
    }
}

class AuthHttpResult {
    let status: UInt16
    let setCookie: ?String
    let body: String
    init(status: UInt16, setCookie: ?String, body: String) {
        this.status = status
        this.setCookie = setCookie
        this.body = body
    }
}

func requestCookie(value: String): String {
    value.split(";")[0]
}

@Test
class AuthTests {
    @TestCase
    func saltedPasswordsAndInvalidCredentials() {
        let a = hashPassword("password123")
        let b = hashPassword("password123")
        @Expect(a.saltHex != b.saltHex, true)
        @Expect(a.hashHex != b.hashHex, true)
        @Expect(a.iterations, 600000)
        @Expect(verifyPassword("password123", a), true)
        @Expect(verifyPassword("incorrect", a), false)
        @Expect(verifyPassword("password123", PasswordDigest()), false)
        let repo = AuthTestRepository()
        let auth = AuthService(repo)
        @Expect(auth.register(AccountKind.User, "alice", "short").isOk(), false)
        let user = auth.register(AccountKind.User, "alice", "password123").unwrap()
        @Expect(user.toJson().toString().contains("password"), false)
        @Expect(auth.register(AccountKind.User, "alice", "password123").isOk(), false)
        @Expect(auth.login(AccountKind.User, "alice", "incorrect").isOk(), false)
        @Expect(auth.login(AccountKind.User, "missing", "password123").isOk(), false)
    }
    @TestCase
    func visitorSurvivesAccountLoginLogoutAndKindsStaySeparate() {
        let repo = AuthTestRepository()
        let auth = AuthService(repo, publicOrigin: "https://example.test")
        let visitor = auth.ensureVisitor("").unwrap()
        let vc = requestCookie(visitor.setCookie.getOrThrow())
        @Expect(visitor.setCookie.getOrThrow().contains("; Secure"), true)
        let again = auth.ensureVisitor(vc).unwrap()
        @Expect(again.actor.visitorId, visitor.actor.visitorId)
        @Expect(again.setCookie.isNone(), true)
        auth.register(AccountKind.User, "same", "password123").unwrap()
        auth.register(AccountKind.Merchant, "same", "password123").unwrap()
        let user = auth.login(AccountKind.User, "same", "password123").unwrap()
        let merchant = auth.login(AccountKind.Merchant, "same", "password123").unwrap()
        let uc = requestCookie(user.setCookie)
        let mc = requestCookie(merchant.setCookie)
        let cookies = vc + "; " + uc + "; " + mc
        let actor = auth.resolve(cookies)
        @Expect(actor.visitorId, visitor.actor.visitorId)
        @Expect(actor.userId, Some(user.account.id))
        @Expect(actor.merchantId, Some(merchant.account.id))
        @Expect(auth.resolve(uc.replace("hw_user=", "hw_merchant=")).merchantId.isNone(), true)
        @Expect(repo.read().authSessions[0].tokenHash != uc.split("=")[1], true)
        auth.logout(AccountKind.User, cookies).unwrap()
        @Expect(auth.me(AccountKind.User, cookies).isOk(), false)
        @Expect(auth.resolve(cookies).merchantId.isSome(), true)
        @Expect(auth.resolve(cookies).visitorId, visitor.actor.visitorId)
        @Expect(repo.read().participants.size, 0)
        @Expect(repo.read().sessions.size, 0)
    }
    @TestCase
    func expirationRotationRecoveryAndWriteFailure() {
        let repo = AuthTestRepository()
        let clock = AuthTestClock()
        let auth = AuthService(repo, clock: clock)
        auth.register(AccountKind.User, "alice", "password123").unwrap()
        let first = requestCookie(auth.login(AccountKind.User, "alice", "password123").unwrap().setCookie)
        let second = requestCookie(auth.login(AccountKind.User, "alice", "password123", cookies: first).unwrap()
            .setCookie)
        @Expect(auth.resolve(first).userId.isNone(), true)
        @Expect(AuthService(repo, clock: clock).resolve(second).userId.isSome(), true)
        @Expect(auth.resolve(second + "; " + second).userId.isNone(), true)
        let before = repo.read().toJson().toString()
        repo.failWrite = true
        @Expect(auth.logout(AccountKind.User, second).isOk(), false)
        @Expect(auth.ensureVisitor("").isOk(), false)
        @Expect(repo.read().toJson().toString(), before)
        @Expect(auth.login(AccountKind.User, "alice", "password123").isOk(), false)
        @Expect(auth.register(AccountKind.Merchant, "failed", "password123").isOk(), false)
        @Expect(repo.read().toJson().toString(), before)
        repo.failWrite = false
        clock.now += 604800000
        @Expect(auth.resolve(second).userId.isNone(), true)
        auth.pruneExpired().unwrap()
        @Expect(repo.read().authSessions.size, 0)
        let visitor = auth.ensureVisitor("").unwrap()
        clock.now += 2592000000
        @Expect(auth.resolve(requestCookie(visitor.setCookie.getOrThrow())).visitorId.isNone(), true)
        auth.pruneExpired().unwrap()
        @Expect(repo.read().visitorSessions.size, 0)
    }

    @TestCase
    func httpLifecycleAndPublicMenuRemainAccessible() {
        let repo = AuthTestRepository()
        let auth = AuthService(repo, publicOrigin: "http://auth.test")
        let defaults = DefaultSettingsService(repo)
        let router = HttpRouter()
        registerAuthRoutes(router, auth, defaults)
        // Public-catalog fixture: B1's catalog implementation is not present yet.
        router.on("GET", "/api/restaurants/TEST/menu", {ctx, _ => jsonResponse(ctx, 200, MenuSnapshot().toJson())})
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
        let client = ClientBuilder().cookieJar(None).build()
        try {
            for (_ in 0..1000) {
                if (ready.load()) {
                    break
                };
                sleep(Duration.millisecond)
            }
            @Expect(ready.load(), true)
            let base = "http://127.0.0.1:${server.port}"
            let request = {
                method: String, path: String, body: String, cookies: String =>
                    let response = client.send(
                        HttpRequestBuilder()
                            .method(method)
                            .url(base + path)
                            .header("origin", "http://auth.test")
                            .header("cookie", cookies)
                            .header("content-type", "application/json")
                            .body(body)
                            .build())
                    AuthHttpResult(response.status, response.headers.getFirst("set-cookie"), readLimited(response.body))
            }
            let visitor = request("POST", "/api/visitor/session", "", "")
            @Expect(visitor.status, 204)
            let vc = requestCookie(visitor.setCookie.getOrThrow())
            let credentials = "{\"login\":\"alice\",\"password\":\"password123\"}"
            let registered = request("POST", "/api/user/register", credentials, vc)
            @Expect(registered.status, 201)
            @Expect(registered.body.contains("password"), false)
            @Expect(request("GET", "/api/user/me", "", vc).status, 401)
            let login = request("POST", "/api/user/login", credentials, vc)
            @Expect(login.status, 200)
            let cookies = vc + "; " + requestCookie(login.setCookie.getOrThrow())
            @Expect(login.body.contains("token"), false)
            let settings = "{\"allergens\":[\"花生\"],\"avoidFoods\":[],\"dietMode\":\"none\",\"maxSpiceLevel\":null,\"tastePreferences\":[]}"
            @Expect(request("PUT", "/api/user/default-settings", settings, cookies).status, 200)
            let loaded = request("GET", "/api/user/default-settings", "", cookies)
            @Expect(loaded.status, 200)
            @Expect(loaded.body.contains("花生"), true)
            @Expect(request("PUT", "/api/user/default-settings", "{\"userId\":\"victim\"}", cookies).status, 400)
            @Expect(request("POST", "/api/user/logout", "", cookies).status, 204)
            @Expect(request("GET", "/api/user/default-settings", "", cookies).status, 401)
            @Expect(request("GET", "/api/restaurants/TEST/menu", "", cookies).status, 200)
            @Expect(auth.resolve(cookies).visitorId, auth.resolve(vc).visitorId)
            for (kind in ["merchant"]) {
                @Expect(request("POST", "/api/" + kind + "/register", credentials, vc).status, 201)
                let signedIn = request("POST", "/api/" + kind + "/login", credentials, vc)
                @Expect(signedIn.status, 200)
                let mc = requestCookie(signedIn.setCookie.getOrThrow())
                @Expect(request("GET", "/api/merchant/me", "", mc).status, 200)
                @Expect(request("GET", "/api/user/default-settings", "", mc).status, 401)
                @Expect(request("POST", "/api/merchant/logout", "", mc).status, 204)
                @Expect(request("GET", "/api/merchant/me", "", mc).status, 401)
            }
            println(
                "B2 HTTP: user register=201 login=200 defaults PUT/GET=200 logout=204 defaults after logout=401 public menu fixture=200; merchant register=201 login=200 me=200 defaults=401 logout=204 me after logout=401")
            let crossOrigin = client.send(
                HttpRequestBuilder()
                    .method("POST")
                    .url(base + "/api/user/login")
                    .header("origin", "https://attacker.test")
                    .body(credentials)
                    .build())
            @Expect(crossOrigin.status, 403)
        } finally {
            client.close();
            server.close();
            worker.get()
        }
    }
}
