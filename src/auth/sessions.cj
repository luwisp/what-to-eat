package juxiaobao.auth

import juxiaobao.model.*

func cookieName(kind: AccountKind): String {
    "hw_" + kind.toWire()
}

// Duplicate cookie names are ambiguous: reject instead of accepting a shadow value.
func cookieHash(cookies: String, name: String): ?String {
    var token: ?String = None
    for (part in cookies.split(";")) {
        let pair = part.trimAscii().split("=")
        if (pair.size == 2 && pair[0] == name) {
            if (token.isSome()) {
                return None
            }
            if (pair[1].size != 64) {
                return None
            }
            try {
                unhex(pair[1])
            } catch (_: Exception) {
                return None
            }
            token = Some(pair[1])
        }
    }
    match (token) {
        case Some(value) => Some(tokenHash(value));
        case None => None
    }
}

func prune(db: DatabaseSnapshot, now: Int64): Unit {
    db.authSessions = db.authSessions.filter({s => s.expiresAt > now})
    db.visitorSessions = db.visitorSessions.filter({s => s.expiresAt > now})
}

func resolveSnapshot(db: DatabaseSnapshot, cookies: String, now: Int64): Actor {
    let actor = Actor()
    let user = cookieHash(cookies, "hw_user")
    let merchant = cookieHash(cookies, "hw_merchant")
    let visitor = cookieHash(cookies, "hw_visitor")
    for (s in db.authSessions) {
        if (s.expiresAt <= now) {
            continue
        }
        if (s.kind == "user" && Some(s.tokenHash) == user && db.users.any({a => a.id == s.accountId})) {
            actor.userId = Some(s.accountId)
        }
        if (s.kind == "merchant" && Some(s.tokenHash) == merchant && db.merchants.any({a => a.id == s.accountId})) {
            actor.merchantId = Some(s.accountId)
        }
    }
    for (s in db.visitorSessions) {
        if (s.expiresAt > now && Some(s.tokenHash) == visitor) {
            actor.visitorId = Some(s.visitorId)
        }
    }
    actor
}
