package juxiaobao.store

import juxiaobao.model.*
import std.sync.*
import std.database.sql.*
import stdx.encoding.json.*
import sqlite4cj.*

// One authoritative snapshot, shared with the offline importer. Publish only after SQLite commits.
public class SqliteRepository <: Repository {
    let path: String
    let lock = Mutex()
    var snapshot = DatabaseSnapshot()
    public init(path: String) {
        this.path = path
        try (ds = SqliteDatasource(path)) {
            try (cn = SqliteConnection(ds)) {
                try (q = cn.prepareStatement("SELECT payload_json FROM app_snapshot WHERE id=1 AND schema_version=1")) {
                    let rows = q.query()
                    if (!rows.next()) {
                        throw Exception("数据库未初始化，请先运行菜单导入")
                    }
                    snapshot = DatabaseSnapshot.fromJson(JsonValue.fromStr(rows.get<String>(0)).asObject())
                }
            }
        }
    }
    public func read(): DatabaseSnapshot {
        synchronized(lock) {
            DatabaseSnapshot.fromJson(snapshot.toJson())
        }
    }
    public func transact(change: (DatabaseSnapshot) -> Outcome<DatabaseSnapshot>): Outcome<Unit> {
        synchronized(lock) {
            try {
                match (change(DatabaseSnapshot.fromJson(snapshot.toJson()))) {
                    case Err(e) => Outcome.Err(e)
                    case Ok(next) =>
                        let detached = DatabaseSnapshot.fromJson(next.toJson())
                        // Escape SQL string literals; no identifier or SQL fragment comes from input.
                        let payload = detached.toJson().toString().replace("'", "''")
                        try (ds = SqliteDatasource(path)) {
                            try (cn = SqliteConnection(ds)) {
                                cn.exec("PRAGMA busy_timeout=5000")
                                let tx = cn.createTransaction()
                                tx.begin()
                                try {
                                    cn.exec("UPDATE app_snapshot SET payload_json='${payload}' WHERE id=1")
                                    tx.commit()
                                } catch (e: Exception) {
                                    tx.rollback();
                                    throw e
                                }
                            }
                        }
                        snapshot = detached
                        Outcome.Ok(())
                }
            } catch (_: Exception) {
                Outcome.Err(DomainError("STORE_FAILED", "数据保存失败，请重试", status: 500))
            }
        }
    }
}
