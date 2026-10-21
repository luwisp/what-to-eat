package juxiaobao.agent

import juxiaobao.model.*
import std.collection.*

// Visible wishes choose a staple implicitly; advanced AI options remain the fallback.
func inferredStaple(p: Preferences, input: RuleInput, facts: Array<MealMetadata>): (String, ?String) {
    var mode = p.stapleMode
    var chosen = p.stapleDishId
    let selected = ArrayList<String>()
    for (id in p.wantedDishIds) { selected.add(id) }
    for (meal in input.menu.setMeals) {
        if (p.wantedSetMealIds.contains(meal.id)) {
            for (c in meal.components) { selected.add(c.dishId) }
        }
    }
    var replacement: ?String = None
    var rice: ?String = None
    for (d in input.menu.dishes) {
        if (!selected.contains(d.id)) { continue }
        let f = findMealMetadata(facts, d.id)
        if (f.role != "staple" || (f.stapleUnits ?? 0) != 1) { continue }
        if (d.name == "米饭" || f.stapleKind == "rice") { rice = Some(d.id) }
        else if (f.stapleKind == "noodles" || d.name.contains("馄饨") || d.name.contains("混沌")) {
            replacement = Some(d.id)
        }
    }
    if (rice.isSome()) { return ("specified", rice) }
    if (p.tastePreferences.contains("米饭")) { return ("default", None) }
    if (replacement.isSome()) { return ("specified", replacement) }
    let noodles = p.tastePreferences.contains("面条")
    let wonton = p.tastePreferences.contains("馄饨") || p.tastePreferences.contains("混沌")
    if (noodles || wonton) {
        var bestPrice: Int64 = Int64.Max
        chosen = None
        for (d in input.menu.dishes) {
            let f = findMealMetadata(facts, d.id)
            let matches = (noodles && f.stapleKind == "noodles") ||
                (wonton && (d.name.contains("馄饨") || d.name.contains("混沌")))
            if (matches && f.role == "staple" && (f.stapleUnits ?? 0) == 1 && d.available &&
                !tableExclusion(input, d) && evaluateMealMemberFit(d, p, input.associations).status == "fit" &&
                d.priceFen < bestPrice) {
                chosen = Some(d.id)
                bestPrice = d.priceFen
            }
        }
        mode = "specified"
    }
    (mode, chosen)
}

public func mealRequestFor(input: RuleInput): MealRequest {
    let facts = input.menu.dishes.map(
        {
            d =>
                for (f in input.menu.mealMetadata) {
                    if (f.dishId == d.id) {
                        return MealMetadata.fromJson(f.toJson())
                    }
                }
                // Legacy fixtures have no annotations. Production imports persist explicit source roles.
                MealMetadata(d.id, role: if (d.category == "hot") {
                    "hotMain"
                } else if (d.category == "cold") {
                    "coldMain"
                } else {
                    d.category
                }, stapleKind: if (d.name == "米饭") {
                    "rice"
                } else {
                    "other"
                }, stapleUnits: if (d.name == "米饭") {
                    Some(1)
                } else {
                    None
                })
        }
    )
    let options = input.members.map(
        {
            m =>
                let p = m.preferences
                let (mode, staple) = inferredStaple(p, input, facts)
                MealMemberOptions(m.id, appetite: p.appetite, stapleMode: mode, stapleDishId: staple,
                    wantedIngredients: p.wantedIngredients,
                    wantedExtras: p.wantedExtras.map({w => MealExtraWish(w.dishId, quantity: w.quantity)}),
                    wantedSpiceLevel: p.wantedSpiceLevel)
        }
    )
    MealRequest(input, facts, options: options)
}

public func recommendMeal(input: RuleInput): Outcome<RecommendationDraft> {
    if (input.menu.mealMetadata.isEmpty()) {
        return buildRuleRecommendation(input)
    }
    if (input.adjustment == Some("addSoup")) {
        var best: ?RecommendationDraft = None
        for (d in input.menu.dishes) {
            if (d.category != "soup") {
                continue
            }
            let checked = checkMealRecommendation(input, input.baseItems.concat([RecommendationItem(itemId: d.id)]))
            if (let Ok(draft) <- checked) {
                if (best.isNone() || draft.totalFen < best.getOrThrow().totalFen) {
                    best = Some(draft)
                }
            }
        }
        if (let Some(draft) <- best) {
            return Outcome.Ok(draft)
        }
        let previous = checkMealRecommendation(input, input.baseItems)
        if (let Ok(draft) <- previous) {
            draft.notices = draft.notices.concat(["没有预算内可追加的适配汤，已保留原方案"])
        }
        return previous
    }
    match (buildMealRecommendation(mealRequestFor(input))) {
        case Ok(report) => Outcome.Ok(report.draft)
        case Err(e) => Outcome.Err(e)
    }
}

public func checkMealRecommendation(input: RuleInput, items: Array<RecommendationItem>): Outcome<RecommendationDraft> {
    if (input.menu.mealMetadata.isEmpty()) {
        return validateRecommendation(input, items)
    }
    return validateMealItems(mealRequestFor(input), items)
}
