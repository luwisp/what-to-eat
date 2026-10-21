package juxiaobao.agent

import juxiaobao.model.*
import std.collection.*

func invalid(message: String): DomainError {
    DomainError("INVALID_RECOMMENDATION", message)
}

func checkedAdd(a: Int64, b: Int64): Int64 {
    if (a < 0 || b < 0 || a > Int64.Max - b) {
        throw IllegalArgumentException("金额或份数超出范围")
    }
    a + b
}

func checkedMultiply(a: Int64, b: Int64): Int64 {
    if (a < 0 || b < 0 || (b > 0 && a > Int64.Max / b)) {
        throw IllegalArgumentException("金额或份数超出范围")
    }
    a * b
}

func findDish(menu: MenuSnapshot, id: String): Dish {
    for (d in menu.dishes) {
        if (d.id == id && d.restaurantId == menu.restaurant.id && d.available && d.priceFen >= 0) {
            return d
        }
    }
    throw IllegalArgumentException("菜品不存在、跨店或不可售：${id}")
}

func findMeal(menu: MenuSnapshot, id: String): SetMeal {
    for (m in menu.setMeals) {
        if (m.id == id && m.restaurantId == menu.restaurant.id && m.priceFen >= 0 && !m.components.isEmpty()) {
            return m
        }
    }
    throw IllegalArgumentException("套餐不存在或无效：${id}")
}

public func evaluateMemberFit(dish: Dish, prefs: Preferences, associations: IngredientAssociations): MemberFit {
    let reasons = ArrayList<String>()
    if (!dish.available) {
        reasons.add("菜品已下架")
    }
    if (let Some(max) <- prefs.maxSpiceLevel) {
        if (dish.spiceLevel > max) {
            reasons.add("超过接受辣度")
        }
    }
    let ingredients = normalizeIngredients(dish.ingredients)
    for (ingredient in ingredients) {
        for (limit in prefs.allergens) {
            if (ingredientMatches(ingredient, limit, associations)) {
                reasons.add("食材${ingredient}匹配过敏项${limit}")
            }
        }
        for (limit in prefs.avoidFoods) {
            if (ingredientMatches(ingredient, limit, associations)) {
                reasons.add("含不吃的${limit}：${ingredient}")
            }
        }
        if (prefs.dietMode != "none" && isAnimalIngredient(ingredient, prefs.dietMode == "plant", associations)) {
            reasons.add("食材${ingredient}不符合饮食模式")
        }
    }
    if (!reasons.isEmpty()) {
        return MemberFit(status: "conflict", reasons: reasons.toArray())
    }
    if (ingredients.contains("unknown")) {
        if (!prefs.allergens.isEmpty() || !prefs.avoidFoods.isEmpty() || prefs.dietMode != "none") {
            return MemberFit(status: "uncertain", reasons: ["食材不完整，暂不计入适合你的菜"])
        }
        return MemberFit(status: "fit", reasons: ["其余食材不详"])
    }
    return MemberFit(status: "fit")
}

public func expandItems(menu: MenuSnapshot, items: Array<RecommendationItem>): Outcome<ExpandedMenu> {
    try {
        let quantities = HashMap<String, Int64>()
        let order = ArrayList<String>()
        var total: Int64 = 0
        for (entry in items) {
            if (entry.quantity <= 0) {
                throw IllegalArgumentException("份数须为正整数")
            }
            let components = ArrayList<SetMealComponent>()
            var price: Int64 = 0
            if (entry.itemType == "dish") {
                let d = findDish(menu, entry.itemId)
                price = d.priceFen
                components.add(SetMealComponent(dishId: d.id))
            } else if (entry.itemType == "setMeal") {
                let m = findMeal(menu, entry.itemId)
                price = m.priceFen
                components.add(all: m.components)
            } else {
                throw IllegalArgumentException("推荐条目类型无效")
            }
            total = checkedAdd(total, checkedMultiply(price, entry.quantity))
            for (component in components) {
                findDish(menu, component.dishId)
                if (component.quantity <= 0) {
                    throw IllegalArgumentException("套餐份数无效")
                }
                if (!quantities.contains(component.dishId)) {
                    order.add(component.dishId)
                }
                quantities[component.dishId] = checkedAdd(quantities.get(component.dishId) ?? 0,
                    checkedMultiply(component.quantity, entry.quantity))
            }
        }
        return Outcome.Ok(
            ExpandedMenu(
                dishes: order.toArray().map({id => ExpandedDish(dish: findDish(menu, id), quantity: quantities[id])}),
                totalFen: total))
    } catch (e: Exception) {
        return Outcome.Err(invalid(e.message))
    }
}

func submitted(input: RuleInput): Array<Participant> {
    input.members.filter({m => m.submitted})
}

func countsAsCoverage(dish: Dish): Bool {
    dish.category == "hot" || dish.category == "cold"
}

func coverage(draft: RecommendationDraft, id: String): Int64 {
    var count: Int64 = 0
    for (f in draft.fits) {
        if (f.memberId == id && f.status == "fit") {
            for (d in draft.expandedDishes) {
                if (d.dish.id == f.dishId && countsAsCoverage(d.dish)) {
                    count++
                }
            }
        }
    }
    count
}

func tableExclusion(input: RuleInput, dish: Dish): Bool {
    for (m in submitted(input)) {
        if (!m.preferences.allergens.isEmpty()) {
            if (normalizeIngredients(dish.ingredients).contains("unknown")) {
                return true
            }
            if (evaluateMemberFit(dish, Preferences(allergens: m.preferences.allergens), input.associations).status !=
                "fit") {
                return true
            }
        }
    }
    false
}

func wishSatisfied(input: RuleInput, expanded: ExpandedMenu, member: Participant, id: String, kind: String): Bool {
    if (kind == "dish") {
        for (d in expanded.dishes) {
            if (d.dish.id == id && evaluateMemberFit(d.dish, member.preferences, input.associations).status == "fit") {
                return true
            }
        }
    }
    return false
}

public func validateRecommendation(input: RuleInput, items: Array<RecommendationItem>): Outcome<RecommendationDraft> {
    let members = submitted(input)
    if (members.isEmpty()) {
        return Outcome.Err(DomainError("NO_SUBMISSIONS", "至少一人提交需求后再推荐"))
    }
    let expansion = expandItems(input.menu, items)
    match (expansion) {
        case Err(e) => return Outcome.Err(e)
        case _ => ()
    }
    let expanded = expansion.unwrap()
    let fits = ArrayList<DishFit>()
    let notices = ArrayList<String>()
    for (d in expanded.dishes) {
        if (tableExclusion(input, d.dish)) {
            return Outcome.Err(invalid("${d.dish.name}因整桌过敏规则排除（含食材不详）"))
        }
        for (m in members) {
            let fit = evaluateMemberFit(d.dish, m.preferences, input.associations)
            if (fit.status == "fit") {
                fits.add(DishFit(dishId: d.dish.id, memberId: m.id, status: fit.status, reasons: fit.reasons))
            } else if (fit.status == "uncertain") {
                notices.add("${m.nickname}：${d.dish.name}食材不完整，暂不计入适合你的菜")
            }
        }
        // A fixed package may include components that fit nobody; eligibility is
        // checked per selected package below, not by banning those components.
        if (normalizeIngredients(d.dish.ingredients).contains("unknown")) {
            notices.add("${d.dish.name}：其余食材不详")
        }
    }
    let canonical = ArrayList<RecommendationItem>()
    for (entry in items) {
        let own = expandItems(input.menu, [entry]).unwrap()
        var anyFit = false
        for (d in own.dishes) {
            for (f in fits) {
                if (f.dishId == d.dish.id) {
                    anyFit = true
                }
            }
        }
        if (!anyFit) {
            return Outcome.Err(invalid("该条目没有适配的已填写成员：${entry.itemId}"))
        }
        if (entry.itemType == "dish") {
            let d = findDish(input.menu, entry.itemId)
            canonical.add(
                RecommendationItem(itemType: "dish", itemId: d.id, quantity: entry.quantity, name: d.name,
                    unitPriceFen: d.priceFen))
        } else {
            let m = findMeal(input.menu, entry.itemId)
            canonical.add(
                RecommendationItem(itemType: "setMeal", itemId: m.id, quantity: entry.quantity, name: m.name,
                    unitPriceFen: m.priceFen))
        }
    }
    let draft = RecommendationDraft(items: canonical.toArray(), expandedDishes: expanded.dishes, fits: fits.toArray(),
        totalFen: expanded.totalFen, notices: notices.toArray(), associations: input.associations)
    let missing = ArrayList<String>()
    let low = ArrayList<String>()
    let wishes = ArrayList<UnmetWish>()
    for (m in members) {
        let count = coverage(draft, m.id)
        if (count == 0) {
            missing.add(m.id)
        } else if (count == 1) {
            low.add(m.id)
        }
        for (id in m.preferences.wantedDishIds) {
            if (!wishSatisfied(input, expanded, m, id, "dish")) {
                wishes.add(
                    UnmetWish(memberId: m.id, itemType: "dish", itemId: id,
                        reason: "未入选：限制、食材不详、不可售或组合取舍；愿望不能覆盖限制"))
            }
        }
        for (id in m.preferences.wantedSetMealIds) {
            var included = false
            for (entry in items) {
                if (entry.itemType == "setMeal" && entry.itemId == id) {
                    for (d in expandItems(input.menu, [entry]).unwrap().dishes) {
                        if (evaluateMemberFit(d.dish, m.preferences, input.associations).status == "fit") {
                            included = true
                        }
                    }
                }
            }
            if (!included) {
                wishes.add(
                    UnmetWish(memberId: m.id, itemType: "setMeal", itemId: id, reason: "套餐未入选或没有适合本人的组分"))
            }
        }
    }
    draft.uncoveredIds = missing.toArray()
    draft.undercoveredIds = low.toArray()
    draft.unmetWishes = wishes.toArray()
    if (let Some(budget) <- input.budgetPerPersonFen) {
        if (budget < 0 || input.people <= 0 || budget > Int64.Max / input.people) {
            return Outcome.Err(invalid("预算或人数无效"))
        }
        let limit = budget * input.people
        if (draft.totalFen > limit) {
            draft.budgetWarning = Some(
                "超出预算${formatMoney(draft.totalFen - limit)}（总价${formatMoney(draft.totalFen)}）")
        }
    }
    return Outcome.Ok(draft)
}

func itemKey(item: RecommendationItem): String {
    "${item.itemType}:${item.itemId}"
}

public func buildRuleRecommendation(input: RuleInput): Outcome<RecommendationDraft> {
    if (input.people <= 0 || input.people > 100) {
        return Outcome.Err(DomainError("INVALID_PEOPLE", "人数须为1至100"))
    }
    let members = submitted(input)
    if (members.isEmpty()) {
        return Outcome.Err(DomainError("NO_SUBMISSIONS", "至少一人提交需求后再推荐"))
    }
    let candidates = ArrayList<RecommendationItem>()
    for (d in input.menu.dishes) {
        candidates.add(RecommendationItem(itemId: d.id))
    }
    for (m in input.menu.setMeals) {
        candidates.add(RecommendationItem(itemType: "setMeal", itemId: m.id))
    }
    let selected = ArrayList<RecommendationItem>()
    if (input.adjustment == Some("addSoup")) {
        selected.add(all: input.baseItems)
        let base = validateRecommendation(input, selected.toArray())
        if (!base.isOk()) {
            return base
        }
        var best: ?RecommendationItem = None
        var bestPrice = Int64.Max
        for (d in input.menu.dishes) {
            if (d.category != "soup") {
                continue
            }
            var present = false
            for (existing in base.unwrap().expandedDishes) {
                if (existing.dish.id == d.id) {
                    present = true
                }
            }
            if (present) {
                continue
            }
            let proposed = selected.toArray().concat([RecommendationItem(itemId: d.id)])
            if (validateRecommendation(input, proposed).isOk() && (d.priceFen < bestPrice || (d.priceFen == bestPrice &&
                d.id < (best ?? RecommendationItem(itemId: "~")).itemId))) {
                best = Some(RecommendationItem(itemId: d.id))
                bestPrice = d.priceFen
            }
        }
        if (let Some(value) <- best) {
            selected.add(value)
        }
        let result = validateRecommendation(input, selected.toArray()).unwrap()
        if (best.isNone()) {
            result.notices = result.notices.concat(["当前没有可追加且适配的汤，已保留原组合"])
        }
        return Outcome.Ok(result)
    }
    let initial = validateRecommendation(input, [])
    if (!initial.isOk()) {
        return initial
    }
    var current = initial.unwrap()
    let options = HashMap<String, Int64>()
    for (m in members) {
        var count: Int64 = 0
        for (d in input.menu.dishes) {
            if (d.available && d.restaurantId == input.menu.restaurant.id && countsAsCoverage(d) &&
                !tableExclusion(input, d) && evaluateMemberFit(d, m.preferences, input.associations).status == "fit") {
                count++
            }
        }
        options[m.id] = count
    }
    // Greedy coverage with stable tie-breaking; no speculative recipe completion.
    // The scarcest member is addressed first, followed by shared coverage gains.
    for (_ in 0..candidates.size) {
        var priority = ""
        var fewest = Int64.Max
        for (m in members) {
            if (coverage(current, m.id) < 2 && options[m.id] > coverage(current, m.id) && (options[m.id] < fewest || (options[m
                    .id] == fewest && m.id < priority))) {
                priority = m.id
                fewest = options[m.id]
            }
        }
        var bestPriority: Int64 = -1
        var best: ?RecommendationItem = None
        var bestDraft: ?RecommendationDraft = None
        var bestScore: Int64 = -1
        var bestOver: Int64 = Int64.Max
        var bestPrice: Int64 = Int64.Max
        var bestWishes: Int64 = -1
        for (candidate in candidates) {
            var already = false
            for (s in selected) {
                if (itemKey(s) == itemKey(candidate)) {
                    already = true
                }
            }
            if (already) {
                continue
            }
            // A package already containing a desired dish satisfies that wish;
            // never add duplicate single portions to chase duplicate wishes.
            if (candidate.itemType == "dish") {
                for (d in current.expandedDishes) {
                    if (d.dish.id == candidate.itemId) {
                        already = true
                    }
                }
            }
            if (already) {
                continue
            }
            let proposed = validateRecommendation(input, selected.toArray().concat([candidate]))
            if (!proposed.isOk()) {
                continue
            }
            let next = proposed.unwrap()
            var score: Int64 = 0
            for (m in members) {
                let before = coverage(current, m.id)
                let after = coverage(next, m.id)
                if (before == 0 && after > 0) {
                    score += 1000000
                }
                if (before < 2 && after > before) {
                    score += if (after >= 2) {
                        200
                    } else {
                        100
                    }
                }
            }
            let wishGain = current.unmetWishes.size - next.unmetWishes.size + tasteScore(input, next) - tasteScore(
                input, current)
            if (score == 0 && wishGain <= 0) {
                continue
            }
            let over: Int64 = if (next.budgetWarning.isSome()) {
                1
            } else {
                0
            }
            let priorityGain: Int64 = if (!priority.isEmpty() && coverage(next, priority) > coverage(current, priority)) {
                1
            } else {
                0
            }
            if (priorityGain > bestPriority || (priorityGain == bestPriority && (score / 1000000 > bestScore / 1000000 ||
                (score / 1000000 == bestScore / 1000000 && (over < bestOver || (over == bestOver && (score > bestScore ||
                (score == bestScore && (wishGain > bestWishes || (wishGain == bestWishes && (next.totalFen < bestPrice ||
                (next.totalFen == bestPrice && itemKey(candidate) < itemKey(best ?? RecommendationItem(itemId: "~")))))))))))))) {
                bestPriority = priorityGain
                best = Some(candidate)
                bestDraft = Some(next)
                bestScore = score
                bestOver = over
                bestPrice = next.totalFen
                bestWishes = wishGain
            }
        }
        if (let Some(entry) <- best) {
            selected.add(entry);
            current = bestDraft.getOrThrow()
        } else {
            break
        }
    }
    // Portions use declared people, including members who have not submitted.
    // This is a simple estimate, not a claim about physical serving weights.
    let estimated = current.items.map({entry => RecommendationItem.fromJson(entry.toJson())})
    for (_ in 0..input.people) {
        var portions: Int64 = 0
        for (d in current.expandedDishes) {
            if (d.quantity >= input.people - portions) {
                portions = input.people
                break
            }
            portions += d.quantity
        }
        if (portions >= input.people || estimated.isEmpty()) {
            break
        }
        var cheapest: Int64 = 0
        for (i in 0..estimated.size) {
            if (estimated[i].unitPriceFen < estimated[cheapest].unitPriceFen || (estimated[i].unitPriceFen == estimated[cheapest]
                .unitPriceFen && itemKey(estimated[i]) < itemKey(estimated[cheapest]))) {
                cheapest = i
            }
        }
        estimated[cheapest].quantity++
        let updated = validateRecommendation(input, estimated)
        if (!updated.isOk()) {
            break
        }
        current = updated.unwrap()
    }
    if (!current.items.isEmpty()) {
        current.notices = current
            .notices
            .concat(["份数按声明人数估算；适合的菜按不同菜品计数。实际份量可在点菜时调整。"])
    }
    return Outcome.Ok(current)
}

func formatMoney(fen: Int64): String {
    let remainder = fen % 100
    let padding = if (remainder < 10) {
        "0"
    } else {
        ""
    }
    "¥${fen / 100}.${padding}${remainder}"
}

func tasteScore(input: RuleInput, draft: RecommendationDraft): Int64 {
    var score: Int64 = 0
    for (m in submitted(input)) {
        for (preference in m.preferences.tastePreferences) {
            var met = false
            for (expanded in draft.expandedDishes) {
                let d = expanded.dish
                if (evaluateMemberFit(d, m.preferences, input.associations).status != "fit") {
                    continue
                }
                if ((preference == "汤" && d.category == "soup") || d.taste.contains(preference) || d
                    .name
                    .contains(preference)) {
                    met = true
                }
                for (ingredient in d.ingredients) {
                    if (ingredientMatches(ingredient, preference, input.associations)) {
                        met = true
                    }
                }
            }
            if (met) {
                score++
            }
        }
    }
    score
}
