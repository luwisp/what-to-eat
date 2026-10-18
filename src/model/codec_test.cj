package huaiwei.model

import stdx.encoding.json.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class ModelCodecTests {
    @TestCase
    func databaseRoundtripRetainsFactsAndIsolation() {
        let before = DatabaseSnapshot()
        before.dishes = [Dish(id: "d1", restaurantId: "r1", name: "土豆", priceFen: 1990,
            ingredients: ["土豆", "unknown"])]
        before.participants = [Participant(id: "p1", visitorId: Some("v1"),
            preferences: Preferences(note: "不要香菜 <script>"),
            draft: Preferences(note: "尚未提交"), joinedAt: 1792310400000)]
        before.sessions = [Session(id: "s1", roomCode: "A3F9", budgetPerPersonFen: Some(5000))]
        let copy = DatabaseSnapshot.fromJson(JsonValue.fromStr(before.toJson().toString()).asObject())
        @Expect(copy.dishes.size, 1)
        @Expect(copy.participants.size, 1)
        @Expect(copy.sessions.size, 1)
        if (copy.dishes.size == 1 && copy.participants.size == 1 && copy.sessions.size == 1) {
            @Expect(copy.dishes[0].priceFen, 1990)
            @Expect(copy.dishes[0].ingredients, ["土豆", "unknown"])
            @Expect(copy.participants[0].joinedAt, 1792310400000)
            @Expect(copy.participants[0].preferences.note, "不要香菜 <script>")
            @Expect(copy.participants[0].draft.note, "尚未提交")
            @Expect(copy.sessions[0].budgetPerPersonFen, Some(5000))
            copy.dishes[0].ingredients[0] = "已修改"
            @Expect(before.dishes[0].ingredients[0], "土豆")
        }
    }
}
