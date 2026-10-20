package huaiwei.agent

import huaiwei.model.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class SearchTests {
    @TestCase
    func hardConstraintsAndPersonalCoverageArePreserved() {
        let input = RuleInput(
            menu: menu(
                [dish("veg1", ["土豆"]), dish("veg2", ["白菜"]), dish("chicken", ["鸡肉"]), dish("peanut", ["花生油"]),
                    dish("unknown", ["unknown"])]),
            members: [member("allergy", prefs: Preferences(allergens: ["花生"])),
                member("plant", prefs: Preferences(dietMode: "plant"))], people: 2)
        let report = buildSearchRecommendation(input, maxExpansions: 100, budgetMillis: 5000).unwrap()
        let draft = validateRecommendation(input, report.optimized.items).unwrap()
        @Expect(draft.uncoveredIds.size, 0)
        @Expect(draft.expandedDishes.any({d => d.dish.id == "peanut" || d.dish.id == "unknown"}), false)
        @Expect(searchCompare(input, report.optimized, report.baseline) != Ordering.GT, true)
    }
    @TestCase
    func deterministicBoundsAndSameInputDoNotMutateMenu() {
        let input = RuleInput(
            menu: menu([dish("a", ["白菜"], price: 100), dish("b", ["土豆"], price: 200), dish("c", ["鸡肉"], price: 300)]),
            members: [member("m")], people: 3, budgetPerPersonFen: Some(1000))
        let before = input.toJson().toString()
        let a = buildSearchRecommendation(input, maxExpansions: 100, budgetMillis: 5000).unwrap()
        let b = buildSearchRecommendation(input, maxExpansions: 100, budgetMillis: 5000).unwrap()
        @Expect(a.optimized.toJson().toString(), b.optimized.toJson().toString())
        @Expect(input.toJson().toString(), before)
        let limited = buildSearchRecommendation(input, maxExpansions: 1).unwrap()
        @Expect(limited.expansions, 1)
        @Expect(limited.stoppedByLimit, true)
        @Expect(validateRecommendation(input, limited.optimized.items).isOk(), true)
    }
    @TestCase
    func fixedPackagePricingUnknownAndNoSubmissions() {
        let input = RuleInput(
            menu: menu(
                [dish("v1", ["白菜"], price: 1000), dish("v2", ["土豆"], price: 1000), dish("u", ["unknown"],
                    price: 1000)],
                meals: [SetMeal(id: "bundle", restaurantId: "r", priceFen: 500,
                    components: [SetMealComponent(dishId: "v1"), SetMealComponent(dishId: "v2"),
                        SetMealComponent(dishId: "u")])]),
            members: [member("plant", prefs: Preferences(dietMode: "plant"))], people: 1)
        let report = buildSearchRecommendation(input, budgetMillis: 5000).unwrap()
        @Expect(report.optimized.totalFen, 500)
        @Expect(report.optimized.uncoveredIds.size, 0)
        @Expect(report.optimized.undercoveredIds.size, 0)
        input.members[0].submitted = false
        @Expect(buildSearchRecommendation(input).isOk(), false)
    }
    @TestCase
    func preferenceGainCannotBeatSafetyAndSoupDoesNotCover() {
        let input = RuleInput(
            menu: menu(
                [dish("rice", ["大米"], category: "staple"), dish("soup", ["鸡肉"], category: "soup"),
                    dish("chicken", ["鸡肉"])]),
            members: [member("plant", prefs: Preferences(dietMode: "plant", wantedDishIds: ["chicken"]))], people: 1)
        let report = buildSearchRecommendation(input).unwrap()
        @Expect(report.optimized.uncoveredIds, ["plant"])
        @Expect(report.optimized.expandedDishes.any({d => d.dish.id == "chicken"}), false)
    }
    @TestCase
    func beamCanReplaceAnExpensiveGreedyCoverageChoice() {
        let input = RuleInput(
            menu: menu(
                [dish("a", ["水"], price: 10000), dish("b", ["甲"], price: 100), dish("c", ["乙"], price: 100),
                    dish("d", ["甲"], price: 200), dish("e", ["乙"], price: 200)]),
            members: [member("m1", prefs: Preferences(avoidFoods: ["乙"])),
                member("m2", prefs: Preferences(avoidFoods: ["甲"]))], people: 2)
        let report = buildSearchRecommendation(input, maxExpansions: 1000, width: 32, budgetMillis: 5000).unwrap()
        @Expect(report.optimized.totalFen, 600)
        @Expect(report.optimized.uncoveredIds.size, 0)
        @Expect(report.optimized.undercoveredIds.size, 0)
        @Expect(report.optimized.totalFen < report.baseline.totalFen, true)
    }
}
