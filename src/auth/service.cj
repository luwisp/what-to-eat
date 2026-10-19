package huaiwei.auth

import huaiwei.model.*
import huaiwei.platform.*
import huaiwei.store.*

public class AuthService <: IdentityResolver {
    public let repository: Repository
    public let clock: Clock
    public let publicOrigin: String
    public init(repository: Repository, clock!: Clock = SystemClock(), publicOrigin!: String = "http://localhost:8080") {
        this.repository = repository
        this.clock = clock
        this.publicOrigin = publicOrigin
    }
    public func register(kind: AccountKind, login: String, password: String): Outcome<AccountView> {
        if (!validCredentials(login, password)) {
            return Outcome.Err(DomainError("INVALID_INPUT", "账号或密码格式无效"))
        }
        let digest = hashPassword(password)
        let id = randomToken()
        let view = AccountView(id: id, kind: kind.toWire(), login: login)
        let result = repository.transact(
            {
                db =>
                    if (findAccount(db, kind, login).isSome()) {
                        return Outcome<DatabaseSnapshot>.Err(DomainError("ACCOUNT_EXISTS", "账号已存在", status: 409))
                    }
                    match (kind) {
                        case User => db.users = db
                            .users
                            .concat(
                                [UserAccount(id: id, login: login, passwordHash: digest, createdAt: clock.wallMillis())])
                        case Merchant => db.merchants = db
                            .merchants
                            .concat(
                                [MerchantAccount(id: id, login: login, passwordHash: digest,
                                    createdAt: clock.wallMillis())])
                    }
                    Outcome<DatabaseSnapshot>.Ok(db)
            }
        )
        match (result) {
            case Ok(_) => Outcome.Ok(view);
            case Err(e) => Outcome.Err(e)
        }
    }
    public func login(kind: AccountKind, login: String, password: String, cookies!: String = ""): Outcome<AuthSession> {
        if (!validCredentials(login, password)) {
            return invalidLogin()
        }
        let db = repository.read()
        let account = findAccount(db, kind, login)
        // Match the cost of an unknown account without keeping a plaintext dummy password.
        var digest = PasswordDigest(algorithm: "pbkdf2-sha256", iterations: 600000,
            saltHex: "00000000000000000000000000000000",
            hashHex: "0000000000000000000000000000000000000000000000000000000000000000")
        if (let Some(view) <- account) {
            match (kind) {
                case User => for (a in db.users) {
                    if (a.id == view.id) {
                        digest = a.passwordHash
                    }
                }
                case Merchant => for (a in db.merchants) {
                    if (a.id == view.id) {
                        digest = a.passwordHash
                    }
                }
            }
        }
        let verified = verifyPassword(password, digest)
        if (!verified || account.isNone()) {
            return invalidLogin()
        }
        let view = account.getOrThrow()
        let token = randomToken()
        let hash = tokenHash(token)
        let previous = cookieHash(cookies, cookieName(kind))
        let result = repository.transact(
            {
                next =>
                    prune(next, clock.wallMillis())
                    next.authSessions = next
                        .authSessions
                        .filter({s => !(s.kind == kind.toWire() && Some(s.tokenHash) == previous)})
                    next.authSessions = next
                        .authSessions
                        .concat(
                            [StoredAuthSession(tokenHash: hash, kind: kind.toWire(), accountId: view.id,
                                expiresAt: clock.wallMillis() + 604800000)])
                    Outcome<DatabaseSnapshot>.Ok(next)
            }
        )
        match (result) {
            case Ok(_) => Outcome.Ok(AuthSession(account: view, setCookie: cookie(cookieName(kind), token, 604800)))
            case Err(e) => Outcome.Err(e)
        }
    }
    public func resolve(cookies: String): Actor {
        resolveSnapshot(repository.read(), cookies, clock.wallMillis())
    }
    public func ensureVisitor(cookies: String): Outcome<VisitorSession> {
        let token = randomToken()
        let visitorId = randomToken()
        let value = VisitorSession()
        let result = repository.transact(
            {
                db =>
                    let now = clock.wallMillis()
                    prune(db, now)
                    let actor = resolveSnapshot(db, cookies, now)
                    if (actor.visitorId.isSome()) {
                        value.actor = actor
                    } else {
                        db.visitorSessions = db
                            .visitorSessions
                            .concat(
                                [StoredVisitorSession(tokenHash: tokenHash(token), visitorId: visitorId,
                                    expiresAt: now + 2592000000)])
                        actor.visitorId = Some(visitorId)
                        value.actor = actor
                        value.setCookie = Some(cookie("hw_visitor", token, 2592000))
                    }
                    Outcome<DatabaseSnapshot>.Ok(db)
            }
        )
        match (result) {
            case Ok(_) => Outcome.Ok(value);
            case Err(e) => Outcome.Err(e)
        }
    }
    // Raw cookie is required to revoke just this browser's session.
    public func logout(kind: AccountKind, cookies: String): Outcome<Unit> {
        let hash = cookieHash(cookies, cookieName(kind))
        repository.transact(
            {
                db =>
                    prune(db, clock.wallMillis())
                    db.authSessions = db
                        .authSessions
                        .filter({s => !(s.kind == kind.toWire() && Some(s.tokenHash) == hash)})
                    Outcome<DatabaseSnapshot>.Ok(db)
            }
        )
    }
    public func me(kind: AccountKind, cookies: String): Outcome<AccountView> {
        let db = repository.read()
        let actor = resolveSnapshot(db, cookies, clock.wallMillis())
        match (kind) {
            case User => for (a in db.users) {
                if (Some(a.id) == actor.userId) {
                    return Outcome.Ok(AccountView(id: a.id, kind: "user", login: a.login, nickname: a.nickname))
                }
            }
            case Merchant => for (a in db.merchants) {
                if (Some(a.id) == actor.merchantId) {
                    return Outcome.Ok(AccountView(id: a.id, kind: "merchant", login: a.login))
                }
            }
        }
        Outcome.Err(DomainError("UNAUTHENTICATED", "请先登录", status: 401))
    }
    public func clearCookie(kind: AccountKind): String {
        cookie(cookieName(kind), "", 0)
    }
    func cookie(name: String, token: String, seconds: Int64): String {
        "${name}=${token}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${seconds}" + if (publicOrigin.startsWith("https://")) {
            "; Secure"
        } else {
            ""
        }
    }
    public func pruneExpired(): Outcome<Unit> {
        repository.transact(
            {
                db =>
                    prune(db, clock.wallMillis());
                    Outcome<DatabaseSnapshot>.Ok(db)
            }
        )
    }
}

func validCredentials(login: String, password: String): Bool {
    if (login.isEmpty() || login.size > 128 || password.size < 8 || password.size > 1024) {
        return false
    }
    for (b in login.toArray()) {
        if (b <= 32 || b == 127) {
            return false
        }
    }
    true
}

func invalidLogin(): Outcome<AuthSession> {
    Outcome.Err(DomainError("INVALID_CREDENTIALS", "账号或密码错误", status: 401))
}

func findAccount(db: DatabaseSnapshot, kind: AccountKind, login: String): ?AccountView {
    match (kind) {
        case User => for (a in db.users) {
            if (a.login == login) {
                return Some(AccountView(id: a.id, kind: "user", login: a.login, nickname: a.nickname))
            }
        }
        case Merchant => for (a in db.merchants) {
            if (a.login == login) {
                return Some(AccountView(id: a.id, kind: "merchant", login: a.login))
            }
        }
    }
    None
}
