package juxiaobao.auth

import juxiaobao.model.*
import stdx.encoding.json.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class DefaultsTests {
    @TestCase
    func defaultsBelongToAuthenticatedUserAndNeverModifyRooms() {
        let repo = AuthTestRepository()
        let auth = AuthService(repo)
        let defaults = DefaultSettingsService(repo)
        @Expect(defaults.get(Actor()).isOk(), false)
        @Expect(defaults.put(Actor(merchantId: Some("merchant")), UserDefaultSettings()).isOk(), false)
        let user = auth.register(AccountKind.User, "alice", "password123").unwrap()
        let actor = Actor(userId: Some(user.id))
        let initial = defaults.get(actor).unwrap()
        @Expect(initial.dietMode, "none")
        @Expect(initial.maxSpiceLevel.isNone(), true)
        @Expect(initial.allergens.size, 0)
        let saved = defaults
            .put(actor,
                UserDefaultSettings(userId: "victim", allergens: ["花生"], avoidFoods: ["香菜"], dietMode: "plant",
                    maxSpiceLevel: Some(1), tastePreferences: ["清淡"]))
            .unwrap()
        @Expect(saved.userId, user.id)
        @Expect(defaults.get(actor).unwrap().allergens, ["花生"])
        @Expect(defaults.get(Actor(userId: Some("victim"))).isOk(), false)
        @Expect(repo.read().sessions.size, 0)
        @Expect(repo.read().participants.size, 0)
        @Expect(repo.read().defaultSettings.size, 1)
        @Expect(defaults.put(actor, UserDefaultSettings(dietMode: "invalid")).isOk(), false)
        @Expect(defaults.put(actor, UserDefaultSettings(maxSpiceLevel: Some(4))).isOk(), false)
        repo.failWrite = true
        @Expect(defaults.put(actor, UserDefaultSettings(allergens: ["虾"])).isOk(), false)
        @Expect(defaults.get(actor).unwrap().allergens, ["花生"])
    }
    @TestCase
    func requestAllowsOnlyLongTermFields() {
        let body = JsonValue
            .fromStr(
                "{\"allergens\":[],\"avoidFoods\":[],\"dietMode\":\"none\",\"maxSpiceLevel\":null,\"tastePreferences\":[]}")
            .asObject()
        @Expect(parseDefaults(body).dietMode, "none")
        for (field in ["userId", "wantedDishIds", "wantedSetMealIds", "note", "budgetFen", "headcount", "updatedAt"]) {
            let bad = JsonValue.fromStr(body.toString()).asObject()
            bad.put(field, JsonString("forbidden"))
            var rejected = false
            try {
                parseDefaults(bad)
            } catch (_: Exception) {
                rejected = true
            }
            @Expect(rejected, true)
        }
    }
}
