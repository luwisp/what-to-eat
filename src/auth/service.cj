package juxiaobao.auth

import juxiaobao.model.*
import juxiaobao.platform.*
import juxiaobao.store.*

class ProfileCell {
    public var value: ?AccountView = None
}

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
        let problem = credentialProblem(login, password)
        if (!problem.isEmpty()) {
            return Outcome.Err(DomainError("INVALID_INPUT", problem))
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
    public func updateProfile(cookies: String, nickname: String): Outcome<AccountView> {
        let value = nickname.trimAscii()
        if (value.toRuneArray().size > 40 || value.toArray().any({b => b < 32 || b == 127})) {
            return Outcome.Err(DomainError("INVALID_INPUT", "用户名最多40字，不能包含换行或控制字符"))
        }
        let saved = ProfileCell()
        let result = repository.transact(
            {
                db =>
                    let actor = resolveSnapshot(db, cookies, clock.wallMillis())
                    if (actor.userId.isNone()) {
                        return Outcome<DatabaseSnapshot>.Err(DomainError("UNAUTHENTICATED", "请先登录", status: 401))
                    }
                    for (user in db.users) {
                        if (Some(user.id) == actor.userId) {
                            user.nickname = if (value.isEmpty()) {
                                None
                            } else {
                                Some(value)
                            }
                            saved.value = Some(
                                AccountView(id: user.id, kind: "user", login: user.login, nickname: user.nickname))
                        }
                    }
                    Outcome.Ok(db)
            }
        )
        match (result) {
            case Err(e) => Outcome.Err(e);
            case Ok(_) => match (saved.value) {
                case Some(view) => Outcome.Ok(view);
                case None => Outcome.Err(DomainError("UNAUTHENTICATED", "请先登录", status: 401))
            }
        }
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

func credentialProblem(login: String, password: String): String {
    if (login.isEmpty()) {
        return "请输入账号"
    }
    if (login.size > 128) {
        return "账号过长，最多128字节"
    }
    for (b in login.toArray()) {
        if (b <= 32 || b == 127) {
            return "账号不能包含空格、换行或控制字符"
        }
    }
    if (password.size < 8) {
        return "密码太短，至少需要8字节（英文或数字至少8位）"
    }
    if (password.size > 1024) {
        return "密码过长，最多1024字节"
    }
    ""
}

func validCredentials(login: String, password: String): Bool {
    credentialProblem(login, password).isEmpty()
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
