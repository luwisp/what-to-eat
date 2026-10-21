package huaiwei.room

import huaiwei.model.*
import huaiwei.store.*
import huaiwei.platform.*
import std.sync.*
import std.unittest.*
import std.unittest.testmacro.*

// Test-only contract fake. It is never mounted as the application's storage.
class TestRepository <: Repository {
    var data = DatabaseSnapshot(restaurants: [Restaurant(id: "r", restaurantCode: "TEST")],
        menuVersions: [MenuVersion(restaurantId: "r", menuVersion: 1)])
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
                    data = DatabaseSnapshot.fromJson(next.toJson())
                    Outcome.Ok(())
                case Err(e) => Outcome.Err(e)
            }
        }
    }
}

class TestClock <: Clock {
    public var now: Int64 = 100000
    public func wallMillis(): Int64 {
        now
    }
    public func monotonicMillis(): Int64 {
        now
    }
}

@Test
class RoomTests {
    @TestCase
    func entryResolverIsReadOnlyAndRejectsLegacyAmbiguity() {
        let repo = TestRepository()
        let clock = TestClock()
        let service = RoomService(repo, clock)
        let room = service.create(Actor(visitorId: Some("h")), CreateSessionInput(restaurantCode: "TEST"), "entry").unwrap()
        @Expect(room.session.roomCode.startsWith("J"), true)
        @Expect(service.resolveEntry("test").unwrap()["kind"].asString().getValue(), "restaurant")
        @Expect(service.resolveEntry(room.session.roomCode.toAsciiLower()).unwrap()["kind"].asString().getValue(), "room")
        @Expect(repo.read().participants.size, 1)
        @Expect(service.resolveEntry("missing").isOk(), false)
        repo.data.restaurants = repo.data.restaurants.concat([Restaurant(id: "other", restaurantCode: room.session.roomCode)])
        @Expect(service.resolveEntry(room.session.roomCode).isOk(), false)
        clock.now += 86400001
        @Expect(service.resolveEntry(room.session.roomCode).unwrap()["kind"].asString().getValue(), "restaurant")
    }
    @TestCase
    func conflictingWishesAreRemovedAndExpiredRoomsArePruned() {
        let repo = TestRepository()
        repo.data.dishes = [Dish(id: "chicken", restaurantId: "r", name: "鸡肉", ingredients: ["鸡肉"])]
        let clock = TestClock()
        let service = RoomService(repo, clock)
        let actor = Actor(visitorId: Some("h"))
        let room = service.create(actor, CreateSessionInput(restaurantCode: "TEST"), "create").unwrap()
        let result = service
            .apply(actor, room.session.roomCode,
                RoomCommand.UpdatePreferences(Preferences(dietMode: "plant", wantedDishIds: ["chicken"]), true),
                room.stateVersion, "submit")
            .unwrap()
        @Expect(result.self.getOrThrow().preferences.wantedDishIds.size, 0)
        let companion = service
            .apply(actor, room.session.roomCode,
                RoomCommand.AddCompanion(Preferences(dietMode: "plant", wantedDishIds: ["chicken"]), ""),
                result.stateVersion, "companion")
            .unwrap()
        @Expect(companion.members[1].preferences.getOrThrow().wantedDishIds.size, 0)
        clock.now += 86400001
        service.pruneExpired()
        @Expect(repo.read().sessions.size, 0)
        @Expect(repo.read().participants.size, 0)
        @Expect(repo.read().dedupeRecords.size, 0)
    }
    @TestCase
    func inviteBeforeFillingAndStableVisitorAcrossLogin() {
        let repo = TestRepository()
        let service = RoomService(repo, TestClock())
        let host = Actor(visitorId: Some("h"))
        let created = service.create(host, CreateSessionInput(restaurantCode: "TEST"), "create-1").unwrap()
        @Expect(created.session.people, 4)
        @Expect(created.self.getOrThrow().submitted, false)
        let guest = service.join(Actor(visitorId: Some("g")), created.session.roomCode).unwrap()
        let submitted = service
            .apply(Actor(visitorId: Some("g")), created.session.roomCode,
                RoomCommand.UpdatePreferences(Preferences(note: "先填"), true), guest.stateVersion, "submit-1")
            .unwrap()
        @Expect(submitted.self.getOrThrow().submitted, true)
        @Expect(service.snapshot(host, created.session.roomCode).unwrap().self.getOrThrow().submitted, false)
        let loggedIn = service.join(Actor(visitorId: Some("g"), userId: Some("user")), created.session.roomCode)
            .unwrap()
        @Expect(loggedIn.self.getOrThrow().id, guest.self.getOrThrow().id)
        @Expect(loggedIn.self.getOrThrow().preferences.note, "先填")
        @Expect(loggedIn.members.size, 2)
        @Expect(service.create(host, CreateSessionInput(restaurantCode: "TEST"), "create-1").unwrap().session.id, created.session.id)
    }

    @TestCase
    func draftsRemainPrivateAndDoNotInvalidateVersions() {
        let service = RoomService(TestRepository(), TestClock())
        let h = Actor(visitorId: Some("h"))
        let g = Actor(visitorId: Some("g"))
        let created = service.create(h, CreateSessionInput(restaurantCode: "TEST"), "create").unwrap()
        let joined = service.join(g, created.session.roomCode).unwrap()
        let draft = service
            .apply(g, created.session.roomCode, RoomCommand.UpdatePreferences(Preferences(note: "私人草稿"), false),
                joined.stateVersion, "draft")
            .unwrap()
        @Expect(draft.stateVersion, joined.stateVersion)
        @Expect(draft.self.getOrThrow().submitted, false)
        let publicView = service.snapshot(h, created.session.roomCode).unwrap()
        @Expect(publicView.members[1].preferences.isNone(), true)
        @Expect(publicView.toJson().toString().contains("私人草稿"), false)
    }

    @TestCase
    func hostCompanionAndVersionPermissions() {
        let service = RoomService(TestRepository(), TestClock())
        let h = Actor(visitorId: Some("h"))
        let g = Actor(visitorId: Some("g"))
        let c = service.create(h, CreateSessionInput(restaurantCode: "TEST", people: 1), "create").unwrap()
        let j = service.join(g, c.session.roomCode).unwrap()
        @Expect(j.session.people, 2)
        @Expect(service.apply(g, c.session.roomCode, RoomCommand.UpdateSession(3, None), j.stateVersion, "forged").isOk(), false)
        let companion = service
            .apply(g, c.session.roomCode, RoomCommand.AddCompanion(Preferences(dietMode: "plant"), ""), j.stateVersion,
                "companion")
            .unwrap()
        @Expect(companion.members.size, 3)
        let companionId = companion.members[2].id
        @Expect(service.apply(h, c.session.roomCode, RoomCommand.RemoveCompanion(companionId), companion.stateVersion, "not-owner").isOk(), false)
        @Expect(service.apply(h, c.session.roomCode, RoomCommand.UpdateSession(1, None), companion.stateVersion, "too-few").isOk(), false)
        @Expect(service.apply(g, c.session.roomCode, RoomCommand.RemoveCompanion(companionId), j.stateVersion, "stale").isOk(), false)
        let removed = service
            .apply(g, c.session.roomCode, RoomCommand.RemoveCompanion(companionId), companion.stateVersion, "remove")
            .unwrap()
        @Expect(removed.members.size, 2)
        @Expect(service.apply(g, c.session.roomCode, RoomCommand.RemoveCompanion(companionId), companion.stateVersion, "remove").unwrap().members.size, 2)
    }

    @TestCase
    func defaultsOnlyPrefillNewSelfAndExpirationRejectsMutations() {
        let repo = TestRepository()
        repo.data.defaultSettings = [UserDefaultSettings(userId: "u", allergens: ["花生"])]
        let clock = TestClock()
        let s = RoomService(repo, clock)
        let a = Actor(visitorId: Some("v"), userId: Some("u"))
        let c = s.create(a, CreateSessionInput(restaurantCode: "TEST"), "create").unwrap()
        @Expect(c.self.getOrThrow().draft.allergens, ["花生"])
        @Expect(c.self.getOrThrow().submitted, false)
        @Expect(c.self.getOrThrow().preferences.allergens.size, 0)
        let restart = RoomService(repo, clock).join(a, c.session.roomCode).unwrap()
        @Expect(restart.self.getOrThrow().id, c.self.getOrThrow().id)
        clock.now += 86400001
        @Expect(s.apply(a, c.session.roomCode, RoomCommand.UpdatePreferences(Preferences(), true), restart.stateVersion, "expired").isOk(), false)
        @Expect(s.create(Actor(), CreateSessionInput(restaurantCode: "TEST"), "anonymous").isOk(), false)
    }
}
