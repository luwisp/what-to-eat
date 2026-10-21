package juxiaobao.store

import juxiaobao.model.*

// All modules share one repository. Implementations belong to teammate B1.
// read returns a detached snapshot. transact gives change an isolated working
// snapshot under a single writer lock; Err/exception/durable-write failure must
// leave both visible memory and durable state unchanged. Commit before unlock.
// Never call other services or callbacks while holding the transaction lock.
public interface Repository {
    func read(): DatabaseSnapshot
    func transact(change: (DatabaseSnapshot) -> Outcome<DatabaseSnapshot>): Outcome<Unit>
}
