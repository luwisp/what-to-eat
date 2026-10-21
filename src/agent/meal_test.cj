package juxiaobao.agent

import juxiaobao.model.*
import juxiaobao.platform.*
import std.unittest.*
import std.unittest.testmacro.*

func mealMeta(id: String, role!: String = "hotMain", vegetable!: Bool = false, primary!: Array<String> = []): MealMetadata {
    MealMetadata(id, role: role, vegetable: vegetable, primaryIngredients: primary,
        stapleUnits: if (role == "staple") {
            Some(1)
        } else {
            None
        }, stapleKind: if (role == "staple") {
            "rice"
        } else {
            "other"
        })
}

func mealFixture(people!: Int64 = 2, budget!: ?Int64 = None, options!: Array<MealMemberOptions> = []): MealRequest {
    let ms = Array<Participant>(people, {i => member("m${i}")})
    let dishes = [dish("a", ["鸡肉"], price: 1000), dish("b", ["白菜"], price: 500),
        dish("rice", ["大米"], price: 100, category: "staple")]
    dishes[2].name = "米饭"
    MealRequest(RuleInput(menu: menu(dishes), members: ms, people: people, budgetPerPersonFen: budget),
        [mealMeta("a", primary: ["鸡肉"]), mealMeta("b", vegetable: true, primary: ["白菜"]),
            mealMeta("rice", role: "staple")], options: options, maxExpansions: 2000, width: 16, budgetMillis: 5000)
}

@Test
class MealTests {
    @TestCase
    func visibleWishesInferStaplesAndRiceOverridesReplacement() {
        let rice = dish("rice", ["大米"], category: "staple")
        rice.name = "米饭"
        let noodles = dish("noodles", ["小麦"], category: "staple")
        noodles.name = "鸡汤面"
        let wonton = dish("wonton", ["小麦"], category: "staple")
        wonton.name = "鸡汤混沌"
        let ms = [member("m")]
        let input = RuleInput(menu: menu([rice, noodles, wonton]), members: ms, people: 1)
        input.menu.mealMetadata = [
            DishMealFacts(dishId: "rice", role: "staple", stapleKind: "rice", stapleUnits: Some(1)),
            DishMealFacts(dishId: "noodles", role: "staple", stapleKind: "noodles", stapleUnits: Some(1)),
            DishMealFacts(dishId: "wonton", role: "staple", stapleUnits: Some(1))]
        ms[0].preferences.tastePreferences = ["面条"]
        @Expect(mealRequestFor(input).options[0].stapleDishId, Some("noodles"))
        ms[0].preferences.tastePreferences = ["馄饨"]
        @Expect(mealRequestFor(input).options[0].stapleDishId, Some("wonton"))
        ms[0].preferences.tastePreferences = []
        ms[0].preferences.wantedDishIds = ["wonton"]
        @Expect(mealRequestFor(input).options[0].stapleDishId, Some("wonton"))
        ms[0].preferences.wantedDishIds = ["wonton", "rice"]
        @Expect(mealRequestFor(input).options[0].stapleDishId, Some("rice"))
        ms[0].preferences.wantedDishIds = []
        ms[0].preferences.tastePreferences = ["馄饨", "米饭"]
        @Expect(mealRequestFor(input).options[0].stapleMode, "default")
        ms[0].preferences.tastePreferences = ["馄饨"]
        ms[0].preferences.avoidFoods = ["小麦"]
        @Expect(mealRequestFor(input).options[0].stapleMode, "specified")
        @Expect(mealRequestFor(input).options[0].stapleDishId.isNone(), true)
        ms[0].preferences.tastePreferences = []
        ms[0].preferences.stapleMode = "none"
        @Expect(mealRequestFor(input).options[0].stapleMode, "none")
    }

    @TestCase
    func modelAdjustmentsUseTheSameMealValidationAndIncludeStaples() {
        let fixture = mealFixture()
        fixture.input.menu.mealMetadata = fixture.metadata.map({m => DishMealFacts(dishId: m.dishId, role: m.role, vegetable: m.vegetable, primaryIngredients: m.primaryIngredients, stapleUnits: m.stapleUnits, stapleKind: m.stapleKind)})
        let clock = AssistantClock()
        let model = ScriptedModel(clock, "{\"items\":[{\"itemType\":\"dish\",\"itemId\":\"a\",\"quantity\":1},{\"itemType\":\"dish\",\"itemId\":\"b\",\"quantity\":1},{\"itemType\":\"dish\",\"itemId\":\"rice\",\"quantity\":2}]}")
        let assistant = DiningAssistant(client: Some(model))
        let initial = assistant.recommend(fixture.input, Deadline(clock, 30000)).unwrap()
        @Expect(initial.draft.mealStatus, "complete")
        let current = Recommendation(mode: "rules", draft: initial.draft)
        let changed = assistant.adjust(fixture.input, current, "保留米饭，重新搭配热菜", [], Deadline(clock,30000)).unwrap()
        @Expect(changed.draft.mealStatus, "complete")
        @Expect(changed.draft.totalFen, 1700)
    }

    @TestCase
    func manualRemovalDoesNotRestoreStaplesAndReportsDeficits() {
        let r = mealFixture()
        let full = buildMealRecommendation(r).unwrap().draft
        let withoutRice = full.items.filter({i => i.itemId != "rice"})
        let changed = validateMealItems(r, withoutRice).unwrap()
        @Expect(changed.items.any({i => i.itemId == "rice"}), false)
        @Expect(changed.mealStatus, "partial")
        @Expect(changed.notices.any({n => n.contains("主食份数不足")}), true)
        @Expect(validateMealItems(r, full.items).unwrap().mealStatus, "complete")
        let limited = mealFixture(budget: Some(1))
        @Expect(validateMealItems(limited, full.items).isOk(), false)
    }

    @TestCase
    func appetiteUsesHalfUnitsAndUnsubmittedNormalReservation() {
        let r = mealFixture(people: 5,
            options: [MealMemberOptions("m0", appetite: "small"), MealMemberOptions("m1", appetite: "normal"),
                MealMemberOptions("m2", appetite: "large"), MealMemberOptions("m3", appetite: "extraLarge"),
                MealMemberOptions("m4", appetite: "normal")])
        @Expect(deriveHotNeed(r),6)
        let small = mealFixture(people: 5,
            options: Array<MealMemberOptions>(5, {i => MealMemberOptions("m${i}", appetite: "small")}))
        @Expect(deriveHotNeed(small),3)
        small.input.members[2].submitted = false
        small.input.members[3].submitted = false
        @Expect(deriveHotNeed(small),4)
    }
    @TestCase
    func completeMealHasSeparateRiceAndRealHotSupply() {
        let r = mealFixture()
        let report = buildMealRecommendation(r).unwrap()
        @Expect(report.status,"complete")
        @Expect(report.hotNeed,2)
        @Expect(report.hotSupply>=2,true)
        @Expect(report.draft.items.filter({i=>i.itemId=="rice"})[0].quantity,2)
        @Expect(report.draft.uncoveredIds.size,0)
        @Expect(report.members.size(),2)
    }
    @TestCase
    func noStapleAndUnverifiedNoodleReplacementAreExplicit() {
        let none = buildMealRecommendation(mealFixture(options: [MealMemberOptions("m0", stapleMode: "none")])).unwrap()
        @Expect(none.draft.items.filter({i=>i.itemId=="rice"})[0].quantity,1)
        @Expect(none.members[0].asObject()["stapleOptOut"].asBool().getValue(),true)
        let unresolved = buildMealRecommendation(mealFixture(options: [MealMemberOptions("m0", stapleMode: "noodles")]))
            .unwrap()
        @Expect(unresolved.status,"partial")
        @Expect(unresolved.deficits.any({s=>s.contains("主食")}),true)
    }
    @TestCase
    func budgetTargetPrefersBandAndNeverOverSpends() {
        let dishes = [dish("a", ["鸡肉"], price: 1000), dish("b", ["牛肉"], price: 2000), dish("c", ["鱼"], price: 2500),
            dish("d", ["虾"], price: 3000), dish("e", ["白菜"], price: 500),
            dish("rice", ["大米"], price: 100, category: "staple")]
        dishes[5].name = "米饭"
        let r = MealRequest(
            RuleInput(menu: menu(dishes), members: Array<Participant>(4, {i => member("m${i}")}), people: 4,
                budgetPerPersonFen: Some(2500)),
            [mealMeta("a"), mealMeta("b"), mealMeta("c"), mealMeta("d"), mealMeta("e", vegetable: true),
                mealMeta("rice", role: "staple")], maxExpansions: 10000, width: 32, budgetMillis: 5000)
        let report = buildMealRecommendation(r).unwrap()
        @Expect(report.status,"complete")
        @Expect(report.targetBandReached,true)
        @Expect(report.draft.totalFen>=9000 && report.draft.totalFen<=10000,true)
        let low = buildMealRecommendation(mealFixture(budget: Some(0))).unwrap()
        @Expect(low.status,"noCandidate")
        @Expect(low.draft.totalFen,0)
    }
    @TestCase
    func porkFactsAndAmbiguousMeatDoNotBecomeFalseFits() {
        let r = mealFixture(options: [])
        r.input.menu.dishes[0].ingredients = ["猪排骨", "熟猪油"]
        r.input.members[0].preferences.avoidFoods = ["猪肉"]
        let f = MealFacts(r)
        @Expect(f.fit[0][0].status,"conflict")
        r.input.menu.dishes[0].ingredients = ["午餐肉"]
        @Expect(MealFacts(r).fit[0][0].status,"uncertain")
        @Expect(MealFacts(r).fit[0][1].status,"fit")
    }
    @TestCase
    func allergyExcludesUnknownAndWishesCannotRestoreIt() {
        let r = mealFixture(options: [MealMemberOptions("m0", wantedIngredients: ["鸡肉"])])
        r.input.members[0].preferences.allergens = ["花生"]
        r.input.menu.dishes[0].ingredients = ["鸡肉", "unknown"]
        let report = buildMealRecommendation(r).unwrap()
        @Expect(report.draft.items.any({i=>i.itemId=="a"}),false)
        @Expect(report.draft.unmetWishes.any({w=>w.itemType=="ingredient"}),true)
    }
    @TestCase
    func extrasNeedEitherABudgetOrExplicitWishAndChickenStockCannotSatisfyMeatWish() {
        let r = mealFixture(options: [MealMemberOptions("m0", wantedIngredients: ["鸡肉"])])
        r.input.menu.dishes[0].ingredients = ["白菜", "鸡精"]
        let report = buildMealRecommendation(r).unwrap()
        @Expect(report.draft.unmetWishes.any({w=>w.itemType=="ingredient"}),true)
        let input = RuleInput(
            menu: menu(
                [dish("hot", ["白菜"], price: 100), dish("snack", ["土豆"], price: 10),
                    dish("milk", ["牛奶"], price: 10, category: "drink")]), members: [member("m")], people: 1)
        let meta = [mealMeta("hot", vegetable: true), mealMeta("snack", role: "side"), mealMeta("milk", role: "drink")]
        let plain = buildMealRecommendation(
            MealRequest(input, meta, options: [MealMemberOptions("m", stapleMode: "none")])).unwrap()
        @Expect(plain.draft.items.any({i=>i.itemId=="snack" || i.itemId=="milk"}),false)
        let extra = buildMealRecommendation(
            MealRequest(input, meta, options: [MealMemberOptions("m", stapleMode: "none", wantedExtraIds: ["milk"])]))
            .unwrap()
        @Expect(extra.draft.items.any({i=>i.itemId=="milk"}),true)
    }
    @TestCase
    func budgetTargetCanAutomaticallyAddSuitableExtras() {
        let input = RuleInput(
            menu: menu(
                [dish("hot", ["白菜"], price: 100), dish("snack", ["土豆"], price: 450),
                    dish("milk", ["牛奶"], price: 400, category: "drink")]), members: [member("m")], people: 1,
            budgetPerPersonFen: Some(1000))
        let meta = [mealMeta("hot", vegetable: true), mealMeta("snack", role: "side"), mealMeta("milk", role: "drink")]
        let report = buildMealRecommendation(
            MealRequest(input, meta, options: [MealMemberOptions("m", stapleMode: "none")],
                maxExpansions: 4000, width: 16, budgetMillis: 5000)).unwrap()
        @Expect(report.targetBandReached,true)
        @Expect(report.draft.totalFen>=950 && report.draft.totalFen<=1000,true)
        @Expect(report.draft.items.any({i=>i.itemId=="snack" || i.itemId=="milk"}),true)
        @Expect(report.draft.items.all({i=>i.quantity<=1}),true)
        @Expect(report.draft.notices.any({n=>n.contains("自动加入适配的小吃或饮料")}),true)
    }
    @TestCase
    func explicitExtrasAllowSeveralKindsAndQuantities() {
        let input = RuleInput(
            menu: menu(
                [dish("hot", ["白菜"], price: 100), dish("snack", ["土豆"], price: 10),
                    dish("milk", ["牛奶"], price: 20, category: "drink")]), members: [member("m")], people: 1)
        let meta = [mealMeta("hot", vegetable: true), mealMeta("snack", role: "side"), mealMeta("milk", role: "drink")]
        let report = buildMealRecommendation(
            MealRequest(input, meta,
                options: [MealMemberOptions("m", stapleMode: "none",
                    wantedExtras: [MealExtraWish("snack", quantity: 2), MealExtraWish("milk", quantity: 3)])],
                maxExpansions: 2000, width: 16, budgetMillis: 5000)).unwrap()
        @Expect(report.draft.items.filter({i=>i.itemId=="snack"})[0].quantity,2)
        @Expect(report.draft.items.filter({i=>i.itemId=="milk"})[0].quantity,3)
        @Expect(report.draft.unmetWishes.size,0)
    }
    @TestCase
    func perMemberAllocationFindsSupplyThatOnlyFitsOthers() {
        let r = mealFixture(people: 2, budget: Some(600), options: [MealMemberOptions("m0", appetite: "extraLarge")])
        r.input.members[0].preferences.avoidFoods = ["白菜"]
        // Two affordable cabbage servings cannot supply the large-appetite chicken-only member.
        let report = buildMealRecommendation(r).unwrap()
        @Expect(report.status,"partial")
        @Expect(report.members[0].asObject()["halfDishAllocated"].asInt().getValue()<4,true)
    }
    @TestCase
    func onlyReviewedNoodleUnitsAreAcceptedAndNeverOverrideWheatAllergy() {
        let r = mealFixture(people: 1)
        r.input.menu.dishes[2].name = "面条"
        r.input.menu.dishes[2].ingredients = ["小麦"]
        let meta = [mealMeta("a"), mealMeta("b", vegetable: true),
            MealMetadata("rice", role: "staple", stapleKind: "noodles")]
        let unconfirmed = buildMealRecommendation(
            MealRequest(r.input, meta,
                options: [MealMemberOptions("m0", stapleMode: "noodles", stapleDishId: Some("rice"))])).unwrap()
        @Expect(unconfirmed.status,"partial")
        let options = [MealMemberOptions("m0", stapleMode: "noodles", stapleDishId: Some("rice"),
            confirmSingleServing: true)]
        let legacyConfirmation = buildMealRecommendation(MealRequest(r.input, meta, options: options)).unwrap()
        @Expect(legacyConfirmation.status,"partial")
        meta[2] = MealMetadata("rice", role: "staple", stapleUnits: Some(1), stapleKind: "noodles")
        let reviewed = buildMealRecommendation(MealRequest(r.input, meta, options: options)).unwrap()
        @Expect(reviewed.status,"complete")
        r.input.members[0].preferences.allergens = ["小麦"]
        let allergic = buildMealRecommendation(MealRequest(r.input, meta, options: options)).unwrap()
        @Expect(allergic.status,"partial")
        @Expect(allergic.draft.items.any({i=>i.itemId=="rice"}),false)
    }
    @TestCase
    func packagePricingAndRiceAreNotDoubleCounted() {
        let dishes = [dish("a", ["土豆"], price: 1000), dish("b", ["白菜"], price: 1000),
            dish("rice", ["大米"], price: 100, category: "staple")]
        dishes[2].name = "米饭"
        let m = menu(dishes,
            meals: [SetMeal(id: "bundle", restaurantId: "r", priceFen: 200,
                components: [SetMealComponent(dishId: "a"), SetMealComponent(dishId: "b"),
                    SetMealComponent(dishId: "rice")])])
        let r = MealRequest(
            RuleInput(menu: m, members: [member("m0"), member("m1")], people: 2, budgetPerPersonFen: Some(150)),
            [mealMeta("a"), mealMeta("b", vegetable: true), mealMeta("rice", role: "staple")])
        let report = buildMealRecommendation(r).unwrap()
        @Expect(report.status,"complete")
        @Expect(report.draft.totalFen,300)
        @Expect(report.draft.items.filter({i=>i.itemId=="rice"})[0].quantity,1)
        @Expect(report.hotSupply,2)
    }
}
