package juxiaobao.auth

import juxiaobao.model.*
import juxiaobao.platform.*
import stdx.crypto.crypto.*
import stdx.crypto.digest.*

func hex(bytes: Array<UInt8>): String {
    let digits = "0123456789abcdef"
    var value = ""
    for (b in bytes) {
        let hi = Int64(b / 16)
        let lo = Int64(b % 16)
        value += digits[hi..hi + 1] + digits[lo..lo + 1]
    }
    value
}

func unhex(value: String): Array<UInt8> {
    if (value.size % 2 != 0) {
        throw IllegalArgumentException("Invalid hex")
    }
    let digits = "0123456789abcdef".toArray()
    let input = value.toArray()
    let result = Array<UInt8>(input.size / 2, repeat: 0)
    for (i in 0..result.size) {
        var n: UInt8 = 0
        for (j in 0..2) {
            var found = false
            for (k in 0..16) {
                if (input[i * 2 + j] == digits[k]) {
                    n = n * 16 + UInt8(k)
                    found = true
                    break
                }
            }
            if (!found) {
                throw IllegalArgumentException("Invalid hex")
            }
        }
        result[i] = n
    }
    result
}

func randomToken(): String {
    hex(SecureRandom(priv: true).nextBytes(32))
}

func tokenHash(token: String): String {
    let digest = SHA256()
    digest.write(token.toArray())
    hex(digest.finish())
}

// OpenSSL PBKDF2-HMAC-SHA256, 600,000 iterations, 128-bit random salt.
public func hashPassword(password: String): PasswordDigest {
    let salt = SecureRandom(priv: true).nextBytes(16)
    PasswordDigest(algorithm: "pbkdf2-sha256", iterations: 600000, saltHex: hex(salt),
        hashHex: hex(pbkdf2Sha256(password.toArray(), salt, 600000)))
}

public func verifyPassword(password: String, stored: PasswordDigest): Bool {
    if (stored.algorithm != "pbkdf2-sha256" || stored.iterations != 600000 || stored.saltHex.size != 32 ||
        stored.hashHex.size != 64) {
        return false
    }
    try {
        let actual = pbkdf2Sha256(password.toArray(), unhex(stored.saltHex), Int32(stored.iterations))
        let expected = unhex(stored.hashHex)
        var difference: UInt8 = 0
        for (i in 0..32) {
            difference = difference | (actual[i] ^ expected[i])
        }
        difference == 0
    } catch (_: Exception) {
        false
    }
}
