package huaiwei.agent

import huaiwei.model.*
import std.unittest.*
import std.unittest.testmacro.*

func dish(id: String, ingredients: Array<String>, price!: Int64 = 1000, category!: String = "hot", spice!: Int64 = 0): Dish {
    Dish(id: id, restaurantId: "r", name: id, ingredients: ingredients, priceFen: price, category: category,
        spiceLevel: spice)
}

func member(id: String, prefs!: Preferences = Preferences(), submitted!: Bool = true): Participant {
    Participant(id: id, submitted: submitted, preferences: prefs)
}

func menu(dishes: Array<Dish>, meals!: Array<SetMeal> = []): MenuSnapshot {
    MenuSnapshot(restaurant: Restaurant(id: "r", restaurantCode: "TEST"), menuVersion: 1, dishes: dishes,
        setMeals: meals)
}

func item(id: String, kind!: String = "dish", quantity!: Int64 = 1): RecommendationItem {
    RecommendationItem(itemId: id, itemType: kind, quantity: quantity)
}

func fits(d: RecommendationDraft, id: String): Int64 {
    var count: Int64 = 0
    for (f in d.fits) {
        if (f.memberId == id && f.status == "fit") {
            count++
        }
    }
    count
}

@Test
class RulesTests {
    let associations = IngredientAssociations()

    @TestCase
    func unknownMatrixAndKnownConflictPrecedence() {
        let potato = dish("u", ["土豆", " UNKNOWN "])
        @Expect(evaluateMemberFit(potato, Preferences(), associations).status, "fit")
        @Expect(evaluateMemberFit(potato, Preferences(avoidFoods: ["香菜"]), associations).status, "uncertain")
        @Expect(evaluateMemberFit(potato, Preferences(dietMode: "plant"), associations).status, "uncertain")
        @Expect(evaluateMemberFit(dish("c", ["鸡肉", "unknown"]), Preferences(dietMode: "ovoLacto"), associations).status, "conflict")
        @Expect(evaluateMemberFit(dish("e", []), Preferences(dietMode: "plant"), associations).status, "uncertain")
        @Expect(evaluateMemberFit(dish("s", ["unknown"], spice: 2), Preferences(maxSpiceLevel: Some(0)), associations).status, "conflict")
    }

    @TestCase
    func fishCrustaceansShellfishAndSeasoningsAreDistinct() {
        @Expect(evaluateMemberFit(dish("f", ["鲫鱼"]), Preferences(allergens: ["鱼"]), associations).status, "conflict")
        @Expect(evaluateMemberFit(dish("f", ["虾"]), Preferences(allergens: ["鱼"]), associations).status, "fit")
        @Expect(evaluateMemberFit(dish("f", ["蛤蜊"]), Preferences(allergens: ["虾蟹"]), associations).status, "fit")
        @Expect(evaluateMemberFit(dish("f", ["蛤蜊"]), Preferences(allergens: ["贝类"]), associations).status, "conflict")
        @Expect(evaluateMemberFit(dish("f", ["花生油"]), Preferences(allergens: ["花生"]), associations).status, "conflict")
        @Expect(evaluateMemberFit(dish("f", ["猪骨汤底"]), Preferences(dietMode: "ovoLacto"), associations).status, "conflict")
        @Expect(evaluateMemberFit(dish("f", ["鸡腿", "鸡翅根"]), Preferences(dietMode: "ovoLacto"), associations).status, "conflict")
        @Expect(evaluateMemberFit(dish("f", ["鸡蛋", "奶酪"]), Preferences(dietMode: "ovoLacto"), associations).status, "fit")
        @Expect(evaluateMemberFit(dish("f", ["鸡蛋", "奶酪"]), Preferences(dietMode: "plant"), associations).status, "conflict")
    }

    @TestCase
    func packagePricesAndCoverageAreNotDoubleCounted() {
        let m = menu([dish("a", ["白菜"]), dish("b", ["牛肉"]), dish("extra", ["青椒"], price: 3200)],
            meals: [SetMeal(id: "meal", restaurantId: "r", priceFen: 12800,
                components: [SetMealComponent(dishId: "a", quantity: 3), SetMealComponent(dishId: "b")])])
        @Expect(expandItems(m, [item("meal", kind: "setMeal"), item("extra")]).unwrap().totalFen, 16000)
        let r = validateRecommendation(
            RuleInput(menu: m, members: [member("veg", prefs: Preferences(dietMode: "plant"))]),
            [item("meal", kind: "setMeal")]).unwrap()
        @Expect(fits(r, "veg"), 1)
        @Expect(r.undercoveredIds, ["veg"])
    }

    @TestCase
    func mixedUnknownPackageKeepsCompleteVegetarianComponents() {
        let m = menu([dish("a", ["白菜"]), dish("b", ["青椒"]), dish("u", ["unknown"])],
            meals: [SetMeal(id: "meal", restaurantId: "r", priceFen: 1500,
                components: [SetMealComponent(dishId: "a"), SetMealComponent(dishId: "b"), SetMealComponent(dishId: "u")])])
        let input = RuleInput(menu: m, members: [member("v", prefs: Preferences(dietMode: "plant"))])
        let r = validateRecommendation(input, [item("meal", kind: "setMeal")]).unwrap()
        @Expect(fits(r, "v"), 2)
        @Expect(r.uncoveredIds.size, 0)
        @Expect(r.undercoveredIds.size, 0)
        input.members = [member("a", prefs: Preferences(allergens: ["花生"]))]
        @Expect(validateRecommendation(input, [item("meal", kind: "setMeal")]).isOk(), false)
    }

    @TestCase
    func unsubmittedAllergyDoesNotExcludeOtherMembersFood() {
        let input = RuleInput(menu: menu([dish("u", ["unknown"])]),
            members: [member("a"), member("draft", prefs: Preferences(allergens: ["花生"]), submitted: false)])
        let result = buildRuleRecommendation(input).unwrap()
        @Expect(result.items.size, 1)
        @Expect(result.undercoveredIds, ["a"])
        @Expect(result.uncoveredIds.size, 0)
        input.members[1].submitted = true
        @Expect(buildRuleRecommendation(input).unwrap().items.size, 0)
    }

    @TestCase
    func personalAvoidanceDoesNotBecomeTableIntersection() {
        let input = RuleInput(menu: menu([dish("mild", ["土豆"]), dish("hot", ["鸡肉"], spice: 3)]),
            members: [member("m", prefs: Preferences(maxSpiceLevel: Some(0))), member("h")])
        let r = buildRuleRecommendation(input).unwrap()
        @Expect(r.items.size, 2)
        @Expect(fits(r, "m"), 1)
        @Expect(fits(r, "h"), 2)
    }

    @TestCase
    func soupAndRiceCannotHideZeroCoverage() {
        let r = validateRecommendation(
            RuleInput(menu: menu([dish("s", ["白菜"], category: "soup"), dish("r", ["大米"], category: "staple")]),
                members: [member("p")]), [item("s"), item("r")]).unwrap()
        @Expect(r.uncoveredIds, ["p"])
        @Expect(r.undercoveredIds.size, 0)
    }

    @TestCase
    func invalidOrUnsellableAndOverflowItemsAreRejected() {
        let d = dish("d", ["土豆"])
        let m = menu([d])
        @Expect(expandItems(m, [item("absent")]).isOk(), false)
        @Expect(expandItems(m, [item("d", quantity: 0)]).isOk(), false)
        @Expect(expandItems(m, [item("d", quantity: Int64.Max)]).isOk(), false)
        d.available = false
        @Expect(expandItems(m, [item("d")]).isOk(), false)
    }

    @TestCase
    func deterministicBudgetWishesAndSoupAdjustment() {
        let input = RuleInput(
            menu: menu(
                [dish("expensive", ["土豆"], price: 5000), dish("b", ["白菜"], price: 500),
                    dish("a", ["青椒"], price: 500), dish("s", ["白菜"], price: 300, category: "soup")]),
            members: [member("p", prefs: Preferences(wantedDishIds: ["absent"]))], people: 1,
            budgetPerPersonFen: Some(1000))
        let first = buildRuleRecommendation(input).unwrap()
        @Expect(first.totalFen, 1000)
        @Expect(first.unmetWishes.size, 1)
        @Expect(first.toJson().toString(), buildRuleRecommendation(input).unwrap().toJson().toString())
        input.baseItems = first.items
        input.adjustment = Some("addSoup")
        let soup = buildRuleRecommendation(input).unwrap()
        @Expect(soup.items.size, 3)
        @Expect(soup.totalFen, 1300)
        @Expect(soup.budgetWarning.isSome(), true)
    }

    @TestCase
    func withinBudgetAlternativeBeatsCostlyPackageWithSameFinalCoverage() {
        let m = menu([dish("a", ["白菜"], price: 500), dish("b", ["青椒"], price: 500)],
            meals: [SetMeal(id: "premium", restaurantId: "r", priceFen: 5000,
                components: [SetMealComponent(dishId: "a"), SetMealComponent(dishId: "b")])])
        let r = buildRuleRecommendation(
            RuleInput(menu: m, members: [member("p")], people: 1, budgetPerPersonFen: Some(1000))).unwrap()
        @Expect(r.totalFen, 1000)
        @Expect(r.budgetWarning.isNone(), true)
    }

    @TestCase
    func portionsUseDeclaredPeopleWhileCoverageStaysDistinct() {
        let r = buildRuleRecommendation(
            RuleInput(menu: menu([dish("a", ["土豆"]), dish("b", ["白菜"])]), members: [member("p")], people: 4))
            .unwrap()
        var portions: Int64 = 0
        for (d in r.expandedDishes) {
            portions += d.quantity
        }
        @Expect(portions >= 4, true)
        @Expect(fits(r, "p"), 2)
    }

    @TestCase
    func quickTastePreferencesAreSoftSelectionGoals() {
        let input = RuleInput(
            menu: menu([dish("a", ["白菜"], price: 500), dish("b", ["土豆"], price: 500),
                dish("fish", ["鲫鱼"], price: 1200)]),
            members: [member("p", prefs: Preferences(tastePreferences: ["鱼"]))], people: 1)
        let result = buildRuleRecommendation(input).unwrap()
        @Expect(result.expandedDishes.any({d => d.dish.id == "fish"}), true)
    }
}
