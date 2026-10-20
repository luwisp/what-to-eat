package huaiwei.room

import huaiwei.model.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class CoordinatorTests {
    @TestCase
    func manualMealEditsRecheckCompletenessAndRejectStaleVersions() {
        let repo = TestRepository()
        repo.data.dishes = [Dish(id: "a", restaurantId: "r", ingredients: ["土豆"], priceFen: 1000),
            Dish(id: "rice", restaurantId: "r", name: "米饭", category: "staple", ingredients: ["大米"], priceFen: 200)]
        repo.data.mealMetadata = [DishMealFacts(dishId: "a", role: "hotMain"),
            DishMealFacts(dishId: "rice", role: "staple", stapleKind: "rice", stapleUnits: Some(1))]
        let rooms = RoomService(repo, TestClock())
        let c = RecommendationCoordinator(rooms)
        let actor = Actor(visitorId: Some("host"))
        let room = rooms.create(actor, CreateSessionInput(restaurantCode: "TEST", people: 1), "create").unwrap()
        rooms.apply(actor, room.session.roomCode, RoomCommand.UpdatePreferences(Preferences(), true), room.stateVersion, "submit").unwrap()
        let job = c.request(actor, room.session.roomCode, "recommend", None).unwrap()
        let full = c.commitResult(job, c.calculate(job).unwrap(), "rules").unwrap()
        @Expect(full.recommendation.getOrThrow().canConfirm, true)
        let items = full.recommendation.getOrThrow().draft.items
        let changed = rooms.apply(actor, room.session.roomCode,
            RoomCommand.EditResult(items.filter({i => i.itemId != "rice"})), full.stateVersion, "remove-rice").unwrap()
        @Expect(changed.recommendation.getOrThrow().canConfirm, false)
        @Expect(changed.recommendation.getOrThrow().draft.mealStatus, "partial")
        @Expect(rooms.apply(actor, room.session.roomCode, RoomCommand.EditResult(items), full.stateVersion, "stale").isOk(), false)
        let restored = rooms.apply(actor, room.session.roomCode, RoomCommand.EditResult(items), changed.stateVersion, "restore").unwrap()
        @Expect(restored.recommendation.getOrThrow().canConfirm, true)
    }

    @TestCase
    func snapshotDetectsMenuChangeEvenIfNotificationFails() {
        let repo = TestRepository()
        repo.data.dishes = [Dish(id: "a", restaurantId: "r", name: "菜", ingredients: ["土豆"])]
        let rooms = RoomService(repo, TestClock())
        let coordinator = RecommendationCoordinator(rooms)
        let actor = Actor(visitorId: Some("h"))
        let room = rooms.create(actor, CreateSessionInput(restaurantCode: "TEST", people: 1), "create").unwrap()
        rooms.apply(actor, room.session.roomCode, RoomCommand.UpdatePreferences(Preferences(), true), room.stateVersion,
            "submit")
        let job = coordinator.request(actor, room.session.roomCode, "rec", None).unwrap()
        coordinator.commitResult(job, coordinator.calculate(job).unwrap(), "rules").unwrap()
        repo.transact(
            {
                db =>
                db.menuVersions[0].menuVersion = 2
                Outcome.Ok(db)
            }
        )
        let latest = rooms.snapshot(actor, room.session.roomCode).unwrap()
        @Expect(latest.recommendationInvalid, true)
        @Expect(latest.recommendation.getOrThrow().canConfirm, false)
    }
    @TestCase
    func oneJobAndStaleMenuResultNeverCommits() {
        let repo = TestRepository()
        repo.data.dishes = [Dish(id: "a", restaurantId: "r", name: "青椒", ingredients: ["青椒"])]
        let clock = TestClock()
        let rooms = RoomService(repo, clock)
        let c = RecommendationCoordinator(rooms)
        let actor = Actor(visitorId: Some("h"))
        let room = rooms.create(actor, CreateSessionInput(restaurantCode: "TEST", people: 1), "create").unwrap()
        let filled = rooms
            .apply(actor, room.session.roomCode, RoomCommand.UpdatePreferences(Preferences(), true), room.stateVersion,
                "submit")
            .unwrap()
        let first = c.request(actor, room.session.roomCode, "rec", None).unwrap()
        let again = c.request(actor, room.session.roomCode, "another-rec", None).unwrap()
        @Expect(first.id, again.id)
        @Expect(repo.read().jobs.size, 1)
        let draft = c.calculate(first).unwrap()
        repo.transact(
            {
                db =>
                db.menuVersions[0].menuVersion = 2
                Outcome.Ok(db)
            }
        )
        c.invalidateRestaurantRooms("r", 2)
        @Expect(c.commitResult(first, draft, "rules").isOk(), false)
        @Expect(rooms.snapshot(actor, filled.session.roomCode).unwrap().recommendation.isNone(), true)
    }

    @TestCase
    func confirmOneDishWarnsAndMenuChangeRevokesAcceptance() {
        let repo = TestRepository()
        repo.data.dishes = [Dish(id: "a", restaurantId: "r", name: "青椒", ingredients: ["青椒"])]
        let rooms = RoomService(repo, TestClock())
        let c = RecommendationCoordinator(rooms)
        let actor = Actor(visitorId: Some("h"))
        let room = rooms.create(actor, CreateSessionInput(restaurantCode: "TEST", people: 1), "create").unwrap()
        let filled = rooms
            .apply(actor, room.session.roomCode, RoomCommand.UpdatePreferences(Preferences(), true), room.stateVersion,
                "submit")
            .unwrap()
        let job = c.request(actor, filled.session.roomCode, "rec", None).unwrap()
        let result = c.commitResult(job, c.calculate(job).unwrap(), "rules").unwrap()
        @Expect(result.recommendation.getOrThrow().canConfirm, true)
        @Expect(result.recommendation.getOrThrow().draft.undercoveredIds.size, 1)
        let closed = rooms
            .apply(actor, room.session.roomCode,
                RoomCommand.Confirm(result.recommendation.getOrThrow().id, result.stateVersion), result.stateVersion,
                "confirm")
            .unwrap()
        @Expect(closed.session.state, "closed")
        repo.transact(
            {
                db =>
                db.menuVersions[0].menuVersion = 2
                db.dishes[0].ingredients = ["青椒", "unknown"]
                Outcome.Ok(db)
            }
        )
        c.invalidateRestaurantRooms("r", 2)
        let invalid = rooms.snapshot(actor, room.session.roomCode).unwrap()
        @Expect(invalid.recommendationInvalid, true)
        @Expect(invalid.recommendation.getOrThrow().accepted, false)
        @Expect(rooms.apply(actor, room.session.roomCode, RoomCommand.UpdatePreferences(Preferences(), true), invalid.stateVersion, "closed-edit").isOk(), false)
        @Expect(rooms.apply(actor, room.session.roomCode, RoomCommand.Reopen, invalid.stateVersion, "reopen").unwrap().session.id, room.session.id)
    }

    @TestCase
    func interruptedJobIsReleasedAndZeroCoverageCannotConfirm() {
        let repo = TestRepository()
        repo.data.dishes = [Dish(id: "u", restaurantId: "r", name: "未知菜", ingredients: ["unknown"])]
        let rooms = RoomService(repo, TestClock())
        let c = RecommendationCoordinator(rooms)
        let actor = Actor(visitorId: Some("h"))
        let r = rooms.create(actor, CreateSessionInput(restaurantCode: "TEST", people: 1), "create").unwrap()
        rooms.apply(actor, r.session.roomCode, RoomCommand.UpdatePreferences(Preferences(dietMode: "plant"), true),
            r.stateVersion, "submit")
        let job = c.request(actor, r.session.roomCode, "rec", None).unwrap()
        let done = c.commitResult(job, c.calculate(job).unwrap(), "rules").unwrap()
        @Expect(done.recommendation.getOrThrow().canConfirm, false)
        @Expect(rooms.apply(actor, r.session.roomCode, RoomCommand.Confirm(done.recommendation.getOrThrow().id, done.stateVersion), done.stateVersion, "confirm").isOk(), false)
        c.request(actor, r.session.roomCode, "rec2", None)
        let afterRestart = RecommendationCoordinator(rooms)
        afterRestart.recoverInterruptedJobs()
        @Expect(afterRestart.request(actor, r.session.roomCode, "rec3", None).isOk(), true)
    }
}
