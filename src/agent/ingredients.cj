package huaiwei.agent

import huaiwei.model.*

// Conservative local associations. Groups deliberately keep fish, crustaceans
// and molluscs distinct. The model can add associations, never remove these.
public func ingredientMatches(raw: String, rawRestriction: String, extra: IngredientAssociations): Bool {
    let ingredient = raw.trimAscii().toAsciiLower()
    let restriction = rawRestriction.trimAscii().toAsciiLower()
    if (ingredient == "unknown" || restriction.isEmpty()) {
        return false
    }
    if (restriction == "鱼") {
        for (name in ["鲍鱼", "鱿鱼", "墨鱼", "章鱼"]) {
            if (ingredient.contains(name)) {
                return false
            }
        }
    }
    if (ingredient.contains(restriction)) {
        return true
    }
    let groups = localIngredientGroups()
    for (group in groups) {
        if (group.ingredient == restriction) {
            for (alias in group.related) {
                if (ingredient.contains(alias)) {
                    return true
                }
            }
        }
    }
    for (entry in extra.entries) {
        if (entry.ingredient.trimAscii().toAsciiLower() == ingredient) {
            for (related in entry.related) {
                // Do not recursively trust model edges or allow it to edit facts.
                if (ingredientMatches(related, restriction, IngredientAssociations())) {
                    return true
                }
            }
        }
    }
    return false
}

func isAnimalIngredient(value: String, plant: Bool, extra: IngredientAssociations): Bool {
    for (group in ["肉类", "鱼", "虾蟹", "贝类"]) {
        if (ingredientMatches(value, group, extra)) {
            return true
        }
    }
    return plant && (ingredientMatches(value, "蛋类", extra) || ingredientMatches(value, "奶", extra) || value
        .contains("蜂蜜"))
}
