import std.env.*
import std.database.sql.*
import sqlite4cj.*

main(): Int64 {
    let path = getVariable("JUXIAOBAO_SQLITE_PROBE_PATH") ?? throw Exception("Probe path required")
    let write = getVariable("JUXIAOBAO_SQLITE_PROBE_WRITE") == Some("true")
    try (ds = SqliteDatasource(path)) {
        try (cn = SqliteConnection(ds)) {
            if (write) {
                cn.exec("CREATE TABLE probe(id INTEGER PRIMARY KEY, ingredients TEXT, price INTEGER)")
                let tx = cn.createTransaction()
                tx.begin()
                cn.exec("INSERT INTO probe VALUES(1, '[\"土豆\",\"unknown\"]', 1990)")
                tx.commit()
                println("SQLite committed: PASS")
            } else {
                try (s = cn.prepareStatement("SELECT ingredients, price FROM probe WHERE id=1")) {
                    let qr = s.query()
                    if (!qr.next() || qr.get<String>(0) != "[\"土豆\",\"unknown\"]" || qr.get<Int64>(1) != 1990) {
                        throw Exception("SQLite restart read failed")
                    }
                    println("SQLite restarted process read: PASS")
                }
            }
        }
    }
    return 0
}
