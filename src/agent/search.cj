package juxiaobao.agent

import juxiaobao.model.*
import juxiaobao.platform.*
import std.collection.*
import std.sort.*
import stdx.encoding.json.*

// Experimental optimizer. Production keeps buildRuleRecommendation unchanged.
public class SearchReport {
    public let baseline: RecommendationDraft
    public var optimized: RecommendationDraft
    public var expansions: Int64 = 0
    public var stoppedByDeadline: Bool = false
    public var stoppedByLimit: Bool = false
    public init(baseline: RecommendationDraft) {
        this.baseline = baseline
        this.optimized = baseline
    }
}

func searchKey(items: Array<RecommendationItem>): String {
    let keys = items.map({i => "${i.itemType}:${i.itemId}:${i.quantity}"})
    sort(keys, by: {
        a, b => if (a < b) {
        Ordering.LT
    } else if (a > b) {
        Ordering.GT
    } else {
        Ordering.EQ
    }
    })
    var result = ""
    for (key in keys) {
        result += key + ";"
    }
    result
}

public func recommendationObjective(input: RuleInput, draft: RecommendationDraft): Array<Int64> {
    var deficit: Int64 = 0
    var wishPeople: Int64 = 0
    for (m in submitted(input)) {
        let n = coverage(draft, m.id)
        if (n < 2) {
            deficit += 2 - n
        }
        let wanted = m.preferences.wantedDishIds.size + m.preferences.wantedSetMealIds.size
        let unmet = draft.unmetWishes.filter({w => w.memberId == m.id}).size
        if (wanted > unmet) {
            wishPeople++
        }
    }
    var over: Int64 = 0
    if (let Some(budget) <- input.budgetPerPersonFen) {
        let limit = checkedMultiply(budget, input.people)
        if (draft.totalFen > limit) {
            over = draft.totalFen - limit
        }
    }
    [draft.uncoveredIds.size, if (over > 0) {
        1
    } else {
        0
    }, over, deficit, -wishPeople, draft.unmetWishes.size, -tasteScore(input, draft), draft.totalFen]
}

func searchCompare(input: RuleInput, a: RecommendationDraft, b: RecommendationDraft): Ordering {
    let left = recommendationObjective(input, a)
    let right = recommendationObjective(input, b)
    for (i in 0..left.size) {
        if (left[i] < right[i]) {
            return Ordering.LT
        }
        if (left[i] > right[i]) {
            return Ordering.GT
        }
    }
    let ak = searchKey(a.items)
    let bk = searchKey(b.items)
    if (ak < bk) {
        Ordering.LT
    } else if (ak > bk) {
        Ordering.GT
    } else {
        Ordering.EQ
    }
}

// A transparent portion estimate, not a serving-weight or satiety guarantee.
// Only hot/cold dishes contribute; extra portions never increase distinct coverage.
func searchPortions(input: RuleInput, draft: RecommendationDraft): RecommendationDraft {
    let items = draft.items.map({i => RecommendationItem.fromJson(i.toJson())})
    var current = draft
    for (_ in 0..input.people) {
        var portions: Int64 = 0
        for (d in current.expandedDishes) {
            if (countsAsCoverage(d.dish)) {
                portions += d.quantity
            }
        }
        if (portions >= input.people || items.isEmpty()) {
            break
        }
        var best: Int64 = -1
        for (i in 0..items.size) {
            let expansion = expandItems(input.menu, [items[i]]).unwrap()
            if (!expansion.dishes.any({
                d => countsAsCoverage(d.dish) && submitted(input).any(
                    {m => evaluateMemberFit(d.dish, m.preferences, input.associations).status == "fit"})
            })) {
                continue
            }
            if (best < 0 || items[i].quantity < items[best].quantity || (items[i].quantity == items[best].quantity && (items[i]
                .unitPriceFen < items[best].unitPriceFen || (items[i].unitPriceFen == items[best].unitPriceFen &&
                itemKey(items[i]) < itemKey(items[best]))))) {
                best = i
            }
        }
        if (best < 0) {
            break
        }
        items[best].quantity++
        current = validateRecommendation(input, items).unwrap()
    }
    current
}

public func buildSearchRecommendation(input: RuleInput, maxExpansions!: Int64 = 480, width!: Int64 = 6,
    budgetMillis!: Int64 = 1200, clock!: Clock = SystemClock()): Outcome<SearchReport> {
    let base = buildRuleRecommendation(input)
    if (let Err(e) <- base) {
        return Outcome.Err(e)
    }
    let report = SearchReport(base.unwrap())
    if (input.adjustment.isSome()) {
        return Outcome.Ok(report)
    }
    if (maxExpansions < 1 || maxExpansions > 5000 || width < 1 || width > 32 || budgetMillis < 1 || budgetMillis > 5000) {
        return Outcome.Err(DomainError("INVALID_SEARCH_CONFIG", "搜索参数超出范围"))
    }
    let deadline = Deadline(clock, budgetMillis)
    let all = ArrayList<RecommendationItem>()
    for (d in input.menu.dishes) {
        all.add(RecommendationItem(itemId: d.id))
    }
    for (m in input.menu.setMeals) {
        all.add(RecommendationItem(itemType: "setMeal", itemId: m.id))
    }
    let candidates = all.toArray()
    sort(candidates, by: {
        a, b => if (itemKey(a) < itemKey(b)) {
        Ordering.LT
    } else if (itemKey(a) > itemKey(b)) {
        Ordering.GT
    } else {
        Ordering.EQ
    }
    })
    let valid = ArrayList<RecommendationItem>()
    for (c in candidates) {
        if (validateRecommendation(input, [c]).isOk()) {
            valid.add(c)
        }
    }
    var beam = [validateRecommendation(input, []).unwrap()]
    let seen = HashSet<String>()
    for (_ in 0..valid.size) {
        let next = ArrayList<RecommendationDraft>()
        for (state in beam) {
            for (candidate in valid) {
                if (deadline.remainingMillis() <= 0) {
                    report.stoppedByDeadline = true
                    return Outcome.Ok(report)
                }
                if (report.expansions >= maxExpansions) {
                    report.stoppedByLimit = true
                    return Outcome.Ok(report)
                }
                if (state.items.any({i => itemKey(i) == itemKey(candidate)})) {
                    continue
                }
                // Skip redundant single dishes already included by a selected package.
                if (candidate.itemType == "dish" && state.expandedDishes.any({d => d.dish.id == candidate.itemId})) {
                    continue
                }
                let items = state.items.concat([candidate])
                let key = searchKey(items)
                if (seen.contains(key)) {
                    continue
                }
                seen.add(key)
                report.expansions++
                let outcome = validateRecommendation(input, items)
                if (!outcome.isOk()) {
                    continue
                }
                let draft = outcome.unwrap()
                next.add(draft)
                let estimated = searchPortions(input, draft)
                if (searchCompare(input, estimated, report.optimized) == Ordering.LT) {
                    report.optimized = estimated
                }
            }
        }
        if (next.isEmpty()) {
            break
        }
        let ranked = next.toArray()
        sort(ranked, by: {a, b => searchCompare(input, a, b)})
        beam = ranked[0..if (ranked.size > width) {
                width
            } else {
                ranked.size
            }]
    }
    return Outcome.Ok(report)
}

public func inspectRuleMenu(input: RuleInput): JsonArray {
    let rows = ArrayList<JsonValue>()
    for (d in input.menu.dishes) {
        let row = JsonObject()
        row.put("dishId", JsonString(d.id))
        row.put("tableExcluded", JsonBool(tableExclusion(input, d)))
        let fits = ArrayList<JsonValue>()
        for (m in submitted(input)) {
            let fit = evaluateMemberFit(d, m.preferences, input.associations)
            let item = JsonObject()
            item.put("memberId", JsonString(m.id));
            item.put("status", JsonString(fit.status))
            item.put("reasons", JsonArray(fit.reasons.map({r => JsonString(r)})))
            fits.add(item)
        }
        row.put("fits", JsonArray(fits.toArray()));
        rows.add(row)
    }
    JsonArray(rows.toArray())
}
