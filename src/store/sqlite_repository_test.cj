package juxiaobao.store

import juxiaobao.model.*
import juxiaobao.platform.*
import std.fs.*
import sqlite4cj.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class SqliteRepositoryTests {
    @TestCase
    func commitsSurviveReconstructionAndFailedWritesKeepPreviousSnapshot() {
        let path = "target/repository-test-${SystemClock().wallMillis()}.sqlite"
        try (ds = SqliteDatasource(path)) {
            try (cn = SqliteConnection(ds)) {
                cn.exec("CREATE TABLE app_snapshot(id INTEGER PRIMARY KEY,schema_version INTEGER,payload_json TEXT)")
                cn.exec("INSERT INTO app_snapshot VALUES(1,1,'${DatabaseSnapshot().toJson()}')")
            }
        }
        try {
            let repo = SqliteRepository(path)
            @Expect(repo.transact({db => db.restaurants = [Restaurant(id: "r", name: "O'Brien 餐馆")]; Outcome.Ok(db)}).isOk(), true)
            @Expect(SqliteRepository(path).read().restaurants[0].name, "O'Brien 餐馆")
            let detached = repo.read(); detached.restaurants[0].name = "不能泄漏"
            @Expect(repo.read().restaurants[0].name, "O'Brien 餐馆")
            try (ds = SqliteDatasource(path)) {
                try (cn = SqliteConnection(ds)) {
                    cn.exec("CREATE TRIGGER reject_write BEFORE UPDATE ON app_snapshot BEGIN SELECT RAISE(ABORT,'injected'); END")
                }
            }
            @Expect(repo.transact({db => db.restaurants[0].name = "不应保存"; Outcome.Ok(db)}).isOk(), false)
            @Expect(repo.read().restaurants[0].name, "O'Brien 餐馆")
            @Expect(SqliteRepository(path).read().restaurants[0].name, "O'Brien 餐馆")
        } finally { removeIfExists(path) }
    }
}
