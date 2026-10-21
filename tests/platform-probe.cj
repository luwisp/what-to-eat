import std.env.*
import stdx.encoding.json.*
import stdx.crypto.crypto.*
import stdx.net.http.*
import stdx.net.tls.*

main(): Int64 {
    let json = JsonValue.fromStr("{\"ingredients\":[\"土豆\",\"unknown\"],\"priceFen\":1990}")
    let copy = JsonValue.fromStr(json.toString()).asObject()
    if (copy["priceFen"].asInt().getValue() != 1990 ||
        copy["ingredients"].asArray()[1].asString().getValue() != "unknown") {
        throw Exception("JSON roundtrip failed")
    }
    let random = SecureRandom(priv: true)
    let first = random.nextBytes(32)
    let second = random.nextBytes(32)
    if (first == second || first.size != 32) { throw Exception("Random source failed") }
    println("JSON Chinese/unknown/integer roundtrip and secure random: PASS")
    if (let Some(url) <- getVariable("JUXIAOBAO_PROBE_HTTPS")) {
        var tls = TlsClientConfig()
        tls.serverName = Some("example.com")
        let client = ClientBuilder().tlsConfig(tls).readTimeout(Duration.second * 10).build()
        try {
            let response = client.get(url)
            if (response.status != 200) { throw Exception("HTTPS status ${response.status}") }
            println("HTTPS with default certificate validation: PASS")
        } finally { client.close() }
    }
    return 0
}
