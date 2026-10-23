package juxiaobao.agent

import juxiaobao.model.*
import juxiaobao.platform.*
import std.collection.*
import std.sort.*
import stdx.encoding.json.*

// v3 lives beside the original rules and v1 search; no shared DTO or production route changes.
public class MealMetadata {
    public let dishId: String
    public let role: String
    public let vegetable: Bool
    public let primaryIngredients: Array<String>
    public let stapleUnits: ?Int64
    public let stapleKind: String
    public let soupGroupId: String
    public let servesMax: ?Int64
    public init(dishId: String, role!: String = "unknown", vegetable!: Bool = false,
        primaryIngredients!: Array<String> = [], stapleUnits!: ?Int64 = None, stapleKind!: String = "other",
        soupGroupId!: String = "", servesMax!: ?Int64 = None) {
        this.dishId = dishId
        this.role = role
        this.vegetable = vegetable
        this.primaryIngredients = primaryIngredients
        this.stapleUnits = stapleUnits
        this.stapleKind = stapleKind
        this.soupGroupId = soupGroupId
        this.servesMax = servesMax
    }
    public static func fromJson(o: JsonObject): MealMetadata {
        MealMetadata(o["dishId"].asString().getValue(), role: o["role"].asString().getValue(),
            vegetable: o["vegetable"].asBool().getValue(),
            primaryIngredients: o["primaryIngredients"]
                .asArray()
                .getItems()
                .toArray()
                .map({v => v.asString().getValue()}), stapleUnits: match (o["stapleUnits"]) {
                case _: JsonNull => None;
                case _ => Some(o["stapleUnits"].asInt().getValue())
            }, stapleKind: o["stapleKind"].asString().getValue(), soupGroupId: o["soupGroupId"].asString().getValue(),
            servesMax: match (o["servesMax"]) {
                case _: JsonNull => None;
                case _ => Some(o["servesMax"].asInt().getValue())
            })
    }
}

public class MealMemberOptions {
    public let memberId: String
    public let appetite: String
    public let stapleMode: String
    public let stapleDishId: ?String
    // Kept only so old experiment code still compiles. It no longer overrides
    // reviewed stapleUnits metadata.
    public let confirmSingleServing: Bool
    public let wantedIngredients: Array<String>
    // Legacy v3 exports store one portion per id. New clients use wantedExtras so
    // one member can explicitly request several portions of the same item.
    public let wantedExtraIds: Array<String>
    public let wantedExtras: Array<MealExtraWish>
    public let wantedSpiceLevel: ?Int64
    public init(memberId: String, appetite!: String = "normal", stapleMode!: String = "default",
        stapleDishId!: ?String = None, confirmSingleServing!: Bool = false, wantedIngredients!: Array<String> = [],
        wantedExtraIds!: Array<String> = [], wantedExtras!: Array<MealExtraWish> = [], wantedSpiceLevel!: ?Int64 = None) {
        this.memberId = memberId
        this.appetite = appetite
        this.stapleMode = stapleMode
        this.stapleDishId = stapleDishId
        this.confirmSingleServing = confirmSingleServing
        this.wantedIngredients = wantedIngredients
        this.wantedExtraIds = wantedExtraIds
        this.wantedExtras = wantedExtras
        this.wantedSpiceLevel = wantedSpiceLevel
    }
}

public class MealExtraWish {
    public let dishId: String
    public let quantity: Int64
    public init(dishId: String, quantity!: Int64 = 1) {
        this.dishId = dishId
        this.quantity = quantity
    }
}

// A new quantity-bearing entry wins over the legacy id list for the same dish,
// preventing clients that send both during migration from double counting.
func mealExtraQuantity(o: MealMemberOptions, dishId: String): Int64 {
    var quantity: Int64 = 0
    var found = false
    for (w in o.wantedExtras) {
        if (w.dishId == dishId) {
            quantity = checkedAdd(quantity, w.quantity)
            found = true
        }
    }
    if (found) {
        return quantity
    }
    for (id in o.wantedExtraIds) {
        if (id == dishId) {
            quantity++
        }
    }
    quantity
}

public func appetiteHalfUnits(value: String): Int64 {
    match (value) {
        case "small" => 1;
        case "normal" => 2;
        case "large" => 3;
        case "extraLarge" => 4
        case _ => throw IllegalArgumentException("饭量须为小、正常、大或特别大")
    }
}

public class MealRequest {
    public let input: RuleInput
    public let metadata: Array<MealMetadata>
    public let options: Array<MealMemberOptions>
    public let maxExpansions: Int64
    public let width: Int64
    public let budgetMillis: Int64
    public init(input: RuleInput, metadata: Array<MealMetadata>, options!: Array<MealMemberOptions> = [],
        maxExpansions!: Int64 = 6000, width!: Int64 = 16, budgetMillis!: Int64 = 2000) {
        this.input = input
        this.metadata = metadata
        this.options = options
        this.maxExpansions = maxExpansions
        this.width = width
        this.budgetMillis = budgetMillis
    }
}

func mealOptions(r: MealRequest, id: String): MealMemberOptions {
    for (o in r.options) {
        if (o.memberId == id) {
            return o
        }
    }
    MealMemberOptions(id)
}

public func deriveHotNeed(r: MealRequest): Int64 {
    let active = submitted(r.input)
    var units = checkedMultiply(r.input.people - active.size, 2)
    for (m in active) {
        units = checkedAdd(units, appetiteHalfUnits(mealOptions(r, m.id).appetite))
    }
    (units + 1) / 2
}

// Additional deterministic facts restrict v3 fits; the original matcher is unchanged.
func mealRuleInput(input: RuleInput): RuleInput {
    let copy = RuleInput.fromJson(input.toJson())
    let entries = ArrayList<IngredientAssociation>(copy.associations.entries)
    for (d in copy.menu.dishes) {
        for (i in d.ingredients) {
            let aliases = ArrayList<String>()
            if (i.contains("猪") || i.contains("五花肉")) {
                aliases.add("猪肉");
                aliases.add("猪")
            }
            if (i.contains("猪油")) {
                aliases.add("猪油")
            }
            if (i.contains("面粉") || i.contains("小麦") || i.contains("挂面")) {
                aliases.add("小麦")
            }
            if (i.contains("鸡肫")) {
                aliases.add("内脏")
            }
            if (!aliases.isEmpty() && !entries.any({e => e.ingredient == i && aliases.toArray().all({a => e.related.contains(a)})})) {
                entries.add(IngredientAssociation(ingredient: i, related: aliases.toArray()))
            }
        }
    }
    copy.associations = IngredientAssociations(entries: entries.toArray())
    copy
}

public func evaluateMealMemberFit(d: Dish, p: Preferences, associations: IngredientAssociations): MemberFit {
    let base = evaluateMemberFit(d, p, associations)
    if (base.status != "fit") {
        return base
    }
    if (d.ingredients.any({i => i.contains("午餐肉")})) {
        if (p.dietMode != "none") {
            return MemberFit(status: "conflict", reasons: ["午餐肉为肉类，不符合饮食模式"])
        }
        if (p.avoidFoods.any({a => a == "猪肉" || a == "猪" || a == "肉类"})) {
            return MemberFit(status: "uncertain", reasons: ["午餐肉未注明肉源，不计为不吃猪肉者适配"])
        }
    }
    base
}

class MealCandidate {
    let item: RecommendationItem
    let components: Array<Int64>
    let componentQuantities: Array<Int64>
    let price: Int64
    let kind: String
    let limit: Int64
    let step: Int64
    let requested: Int64
    init(item: RecommendationItem, components: Array<Int64>, quantities: Array<Int64>, price: Int64, kind: String,
        limit!: Int64 = 2, step!: Int64 = 1, requested!: Int64 = 0) {
        this.item = item
        this.components = components
        this.componentQuantities = quantities
        this.price = price
        this.kind = kind
        this.limit = limit
        this.step = step
        this.requested = requested
    }
}

func mealCandidateNext(c: MealCandidate, current: Int64): Array<Int64> {
    let values = ArrayList<Int64>()
    if (current + c.step <= c.limit) { values.add(current + c.step) }
    if (c.requested > current && c.requested <= c.limit && c.requested != current + c.step) {
        values.add(c.requested)
    }
    values.toArray()
}

let mealAutoExtraQuantityLimit: Int64 = 12

class MealState {
    let q: Array<Int64>
    let dishQ: Array<Int64>
    let cost: Int64
    let score: Array<Int64>
    let hot: Int64
    let coverage: Array<Int64>
    let allocated: Array<Int64>
    let stapleIds: Array<String>
    let deficits: Array<String>
    let wishes: Array<UnmetWish>
    let complete: Bool
    init(q: Array<Int64>, dishQ: Array<Int64>, cost: Int64, score: Array<Int64>, hot: Int64, coverage: Array<Int64>,
        allocated: Array<Int64>, stapleIds: Array<String>, deficits: Array<String>, wishes: Array<UnmetWish>) {
        this.q = q
        this.dishQ = dishQ
        this.cost = cost
        this.score = score
        this.hot = hot
        this.coverage = coverage
        this.allocated = allocated
        this.stapleIds = stapleIds
        this.deficits = deficits
        this.wishes = wishes
        this.complete = deficits.isEmpty()
    }
}

func findMealMetadata(values: Array<MealMetadata>, id: String): MealMetadata {
    for (m in values) {
        if (m.dishId == id) {
            return m
        }
    }
    MealMetadata(id)
}

class MealFacts {
    let r: MealRequest
    let input: RuleInput
    let members: Array<Participant>
    let dishes: Array<Dish>
    let meta: Array<MealMetadata>
    let fit: Array<Array<MemberFit>>
    let excluded: Array<Bool>
    let explicitQuantities: Array<Int64>
    let hotLimit: Int64
    let soupLimit: Int64
    let hotNeed: Int64
    let budget: ?Int64
    let halfNeeds: Array<Int64>
    let stapleChoice: Array<Int64>
    let stapleUnits: Array<Int64>
    let candidates: ArrayList<MealCandidate> = ArrayList<MealCandidate>()
    init(r: MealRequest) {
        this.r = r
        let parsed = mealRuleInput(r.input);
        input = parsed
        let active = submitted(parsed);
        members = active
        dishes = parsed.menu.dishes
        hotNeed = deriveHotNeed(r)
        budget = match (input.budgetPerPersonFen) {
            case Some(b) => Some(checkedMultiply(b, input.people));
            case None => None
        }
        meta = dishes.map({d => findMealMetadata(r.metadata, d.id)})
        fit = dishes.map({d => active.map({m => evaluateMealMemberFit(d, m.preferences, parsed.associations)})})
        excluded = dishes.map(
            {d => tableExclusion(parsed, d) || !d.available || d.restaurantId != parsed.menu.restaurant.id})
        explicitQuantities = dishes.map({d =>
            var total: Int64 = 0
            for (m in active) {
                if (evaluateMealMemberFit(d, m.preferences, parsed.associations).status == "fit") {
                    total = checkedAdd(total, mealExtraQuantity(mealOptions(r, m.id), d.id))
                }
            }
            total
        })
        var hotExtra: Int64 = 0
        var soups: Int64 = 0
        for (di in 0..dishes.size) {
            if (meta[di].role == "hotMain" && explicitQuantities[di] > 2) {
                hotExtra = checkedAdd(hotExtra, explicitQuantities[di] - 2)
            }
            if (meta[di].role == "soup") { soups = checkedAdd(soups, explicitQuantities[di]) }
        }
        hotLimit = checkedAdd(2 * hotNeed, hotExtra)
        soupLimit = if (soups > 1) { soups } else { 1 }
        halfNeeds = members.map({m => appetiteHalfUnits(mealOptions(r, m.id).appetite)})
        stapleChoice = Array<Int64>(input.people, repeat: -1)
        stapleUnits = meta.map({m => m.stapleUnits ?? 0})
        for (mi in 0..input.people) {
            let o = if (mi < members.size) {
                mealOptions(r, members[mi].id)
            } else {
                MealMemberOptions("")
            }
            if (o.stapleMode == "none") {
                stapleChoice[mi] = -2
                continue
            }
            var best: Int64 = -1
            for (di in 0..dishes.size) {
                if (excluded[di] || meta[di].role != "staple" || (mi < members.size && fit[di][mi].status != "fit")) {
                    continue
                }
                let allowed = if (o.stapleMode == "default") {
                    meta[di].stapleKind == "rice" && dishes[di].name == "米饭"
                } else if (o.stapleMode == "noodles") {
                    meta[di].stapleKind == "noodles" && (o.stapleDishId.isNone() || o.stapleDishId == Some(
                        dishes[di].id))
                } else {
                    o.stapleDishId == Some(dishes[di].id)
                }
                if (!allowed || (meta[di].stapleUnits ?? 0) != 1) {
                    continue
                }
                if (best < 0 || dishes[di].priceFen < dishes[best].priceFen || (dishes[di].priceFen == dishes[best]
                    .priceFen && dishes[di].id < dishes[best].id)) {
                    best = di
                }
            }
            stapleChoice[mi] = best
            if (best >= 0) {
                stapleUnits[best] = 1
            }
        }
        let sorted = ArrayList<RecommendationItem>()
        for (d in dishes) {
            sorted.add(RecommendationItem(itemId: d.id))
        }
        for (m in input.menu.setMeals) {
            sorted.add(RecommendationItem(itemType: "setMeal", itemId: m.id))
        }
        let items = sorted.toArray()
        sort(items, by: {a, b => mealStringOrder(itemKey(a), itemKey(b))})
        for (item in items) {
            let expansion = expandItems(input.menu, [item])
            if (!expansion.isOk()) {
                continue
            }
            let indexes = ArrayList<Int64>();
            let quantities = ArrayList<Int64>()
            var valid = true;
            var hasFit = false;
            var hasHot = false;
            var hasSoup = false;
            var extraLimit: Int64 = 0
            var autoExtra = false
            var requestedLimit: Int64 = 0
            for (e in expansion.unwrap().dishes) {
                var index: Int64 = -1
                for (i in 0..dishes.size) {
                    if (dishes[i].id == e.dish.id) {
                        index = i
                        break
                    }
                }
                if (index < 0 || excluded[index]) {
                    valid = false
                    break
                }
                if (fit[index].any({f => f.status == "fit"})) {
                    hasFit = true
                }
                let requestedUnits = (explicitQuantities[index] + e.quantity - 1) / e.quantity
                if (requestedUnits > requestedLimit) { requestedLimit = requestedUnits }
                let role = meta[index].role
                if (role == "unknown") {
                    valid = false
                    break
                }
                if (role == "hotMain") {
                    hasHot = true
                }
                if (role == "soup") {
                    hasSoup = true
                }
                if (role == "side" || role == "drink" || role == "coldMain") {
                    var requested: Int64 = 0
                    for (mi in 0..members.size) {
                        let quantity = mealExtraQuantity(mealOptions(r, members[mi].id), e.dish.id)
                        let wanted = if (quantity > 0) {
                            quantity
                        } else if (members[mi].preferences.wantedDishIds.contains(e.dish.id)) {
                            1
                        } else {
                            0
                        }
                        if (wanted > 0 && fit[index][mi].status == "fit") {
                            requested = checkedAdd(requested, wanted)
                        }
                    }
                    let itemQuantity = if (requested == 0) {
                        if (r.input.budgetPerPersonFen.isNone()) {
                            valid = false
                            break
                        }
                        autoExtra = true
                        mealAutoExtraQuantityLimit
                    } else {
                        (requested + e.quantity - 1) / e.quantity
                    }
                    if (itemQuantity > extraLimit) {
                        extraLimit = itemQuantity
                    }
                }
                indexes.add(index);
                quantities.add(e.quantity)
            }
            if (!valid || !hasFit) {
                continue
            }
            // Single staples are allocated automatically, not added to inflate the budget.
            if (!hasHot && !hasSoup && extraLimit == 0) {
                continue
            }
            let kind = if (hasHot) {
                "hot"
            } else if (hasSoup) {
                "soup"
            } else {
                "extra"
            }
            let normalLimit = if (kind == "hot") { 2 } else if (kind == "soup") { 1 } else { extraLimit }
            let limit = if (requestedLimit > normalLimit) { requestedLimit } else { normalLimit }
            candidates.add(
                MealCandidate(item, indexes.toArray(), quantities.toArray(), expansion.unwrap().totalFen, kind,
                    limit: limit, requested: requestedLimit, step: if (kind == "extra" && !autoExtra) {
                        limit
                    } else {
                        1
                    }))
        }
    }
}

func mealExplicitExtraNeed(f: MealFacts, dishIndex: Int64): Int64 {
    var need: Int64 = 0
    for (mi in 0..f.members.size) {
        if (f.fit[dishIndex][mi].status == "fit") {
            let quantity = mealExtraQuantity(mealOptions(f.r, f.members[mi].id), f.dishes[dishIndex].id)
            need = checkedAdd(need, if (quantity > 0) {
                quantity
            } else if (f.members[mi].preferences.wantedDishIds.contains(f.dishes[dishIndex].id)) {
                1
            } else {
                0
            })
        }
    }
    need
}

func mealSearchSteps(f: MealFacts): Int64 {
    var steps = 2 * f.hotNeed + 3
    if (f.budget.isSome()) {
        for (c in f.candidates) {
            if (c.kind == "extra") {
                steps = checkedAdd(steps, c.limit)
            }
        }
    }
    if (steps > 64) {
        64
    } else {
        steps
    }
}

func mealStringOrder(a: String, b: String): Ordering {
    if (a < b) {
        Ordering.LT
    } else if (a > b) {
        Ordering.GT
    } else {
        Ordering.EQ
    }
}

func mealStateKey(q: Array<Int64>): String {
    var s = "";
    for (v in q) {
        s += "${v},"
    };
    s
}

func mealStateOrder(a: MealState, b: MealState): Ordering {
    for (i in 0..a.score.size) {
        if (a.score[i] < b.score[i]) {
            return Ordering.LT
        };
        if (a.score[i] > b.score[i]) {
            return Ordering.GT
        }
    }
    mealStringOrder(mealStateKey(a.q), mealStateKey(b.q))
}

// Integer max flow: each hot serving supplies two policy half-dish units, not measured weight.
func mealAllocate(f: MealFacts, dishQ: Array<Int64>,
    portions!: ?ArrayList<Array<MealDishPortion>> = None): Array<Int64> {
    let selected = ArrayList<Int64>()
    for (di in 0..f.dishes.size) {
        if (dishQ[di] > 0 && f.meta[di].role == "hotMain") {
            selected.add(di)
        }
    }
    let pending = f.input.people - f.members.size
    let demands = f.halfNeeds.concat(if (pending > 0) {
        [2 * pending]
    } else {
        []
    })
    let n = 2 + selected.size + demands.size
    let sink = n - 1
    let residual = Array<Array<Int64>>(n, {_ => Array<Int64>(n, repeat: 0)})
    for (j in 0..selected.size) {
        let di = selected[j];
        residual[0][1 + j] = 2 * dishQ[di]
        for (mi in 0..demands.size) {
            if (mi >= f.members.size || f.fit[di][mi].status == "fit") {
                residual[1 + j][1 + selected.size + mi] = 2 * dishQ[di]
            }
        }
    }
    for (mi in 0..demands.size) {
        residual[1 + selected.size + mi][sink] = demands[mi]
    }
    while (true) {
        let parent = Array<Int64>(n, repeat: -1);
        parent[0] = 0
        let queue = ArrayList<Int64>();
        queue.add(0);
        var head: Int64 = 0
        while (head < queue.size && parent[sink] < 0) {
            let u = queue[head];
            head++
            for (v in 0..n) {
                if (parent[v] < 0 && residual[u][v] > 0) {
                    parent[v] = u
                    queue.add(v)
                }
            }
        }
        if (parent[sink] < 0) {
            break
        }
        var amount = Int64.Max;
        var v = sink
        while (v != 0) {
            let u = parent[v];
            if (residual[u][v] < amount) {
                amount = residual[u][v]
            };
            v = u
        }
        v = sink
        while (v != 0) {
            let u = parent[v];
            residual[u][v] -= amount
            residual[v][u] += amount
            v = u
        }
    }
    if (let Some(rows) <- portions) {
        for (mi in 0..demands.size) {
            let dishes = ArrayList<MealDishPortion>()
            for (j in 0..selected.size) {
                let units = residual[1 + selected.size + mi][1 + j]
                if (units > 0) {
                    dishes.add(MealDishPortion(dishId: f.dishes[selected[j]].id, halfDishUnits: units))
                }
            }
            rows.add(dishes.toArray())
        }
    }
    Array<Int64>(demands.size, {mi => demands[mi] - residual[1 + selected.size + mi][sink]})
}

func mealEvaluate(f: MealFacts, q: Array<Int64>, enforceBudget!: Bool = true, manual!: ?ExpandedMenu = None): ?MealState {
    let dishQ = Array<Int64>(f.dishes.size, repeat: 0)
    var cost: Int64 = 0
    for (ci in 0..q.size) {
        let c = f.candidates[ci]
        if (q[ci] < 0 || q[ci] > c.limit) {
            return None
        }
        cost = checkedAdd(cost, checkedMultiply(q[ci], c.price))
        for (j in 0..c.components.size) {
            dishQ[c.components[j]] = checkedAdd(dishQ[c.components[j]], checkedMultiply(q[ci], c.componentQuantities[j]))
        }
    }
    if (let Some(expanded) <- manual) {
        cost = expanded.totalFen
        for (di in 0..f.dishes.size) {
            dishQ[di] = 0
            for (d in expanded.dishes) { if (d.dish.id == f.dishes[di].id) { dishQ[di] = d.quantity } }
        }
    }
    let needed = Array<Int64>(f.dishes.size, repeat: 0)
    let stapleIds = Array<String>(f.input.people, repeat: "")
    let deficits = ArrayList<String>()
    for (mi in 0..f.stapleChoice.size) {
        let di = f.stapleChoice[mi]
        if (di >= 0) {
            let requested = if (mi < f.members.size) {
                mealExtraQuantity(mealOptions(f.r, f.members[mi].id), f.dishes[di].id)
            } else { 0 }
            needed[di] = checkedAdd(needed[di], if (requested > 0) { requested } else { 1 });
            stapleIds[mi] = f.dishes[di].id
        } else if (di == -1) {
            deficits.add(
                "${if (mi < f.members.size) { f.members[mi].nickname } else { "未提交成员" }}缺少适配且已核对为单人份的主食")
        }
    }
    for (di in 0..dishQ.size) {
        if (f.meta[di].role == "staple" && dishQ[di] > needed[di] && manual.isNone()) {
            return None
        }
        let add = needed[di] - dishQ[di]
        if (add > 0 && manual.isSome()) { deficits.add("主食份数不足：${f.dishes[di].name}") }
        if (add > 0 && manual.isNone()) {
            cost = checkedAdd(cost, checkedMultiply(add, f.dishes[di].priceFen))
            dishQ[di] += add
        }
    }
    if (manual.isSome()) {
        let available = dishQ.clone()
        for (mi in 0..f.stapleChoice.size) {
            let di = f.stapleChoice[mi]
            if (di >= 0) {
                if (available[di] > 0) { available[di]-- } else { stapleIds[mi] = "" }
            }
        }
    }
    if (enforceBudget) {
        if (let Some(b) <- f.budget) {
            if (cost > b) {
                return None
            }
        }
    }
    var hot: Int64 = 0;
    var distinct: Int64 = 0;
    var vegetables: Int64 = 0;
    var soup: Int64 = 0
    let coverage = Array<Int64>(f.members.size, repeat: 0)
    for (di in 0..dishQ.size) {
        if (dishQ[di] <= 0) {
            continue
        }
        if (f.meta[di].role == "hotMain") {
            if (dishQ[di] > 2 && dishQ[di] > f.explicitQuantities[di]) {
                return None
            }
            hot += dishQ[di]
            distinct++
            if (f.meta[di].vegetable) {
                vegetables++
            }
            for (mi in 0..f.members.size) {
                if (f.fit[di][mi].status == "fit") {
                    coverage[mi]++
                }
            }
        }
        if (f.meta[di].role == "soup") {
            soup += dishQ[di]
        }
    }
    if (hot > f.hotLimit || soup > f.soupLimit) {
        return None
    }
    let allocated = mealAllocate(f, dishQ)
    var allocationGap: Int64 = 0;
    var zero: Int64 = 0;
    var choiceGap: Int64 = 0
    for (mi in 0..f.members.size) {
        if (coverage[mi] == 0) {
            zero++;
            deficits.add("${f.members[mi].nickname}没有适配热菜")
        }
        let gap = f.halfNeeds[mi] - allocated[mi]
        if (gap > 0) {
            allocationGap += gap
            deficits.add("${f.members[mi].nickname}饭量估算缺${gap}个半道菜单位")
        }
        let goal = if (f.hotNeed < 2) {
            f.hotNeed
        } else {
            2
        }
        if (coverage[mi] < goal) {
            choiceGap += goal - coverage[mi]
        }
    }
    if (allocated.size > f.members.size) {
        let gap = 2 * (f.input.people - f.members.size) - allocated[f.members.size]
        if (gap > 0) {
            allocationGap += gap
            deficits.add("未提交成员的正常饭量预留不足")
        }
    }
    let hotGap = if (hot < f.hotNeed) {
        f.hotNeed - hot
    } else {
        0
    }
    if (hotGap > 0) {
        deficits.add("整桌热菜缺${hotGap}份")
    }
    let wishes = ArrayList<UnmetWish>();
    var wishPeople: Int64 = 0
    for (mi in 0..f.members.size) {
        let m = f.members[mi];
        let o = mealOptions(f.r, m.id);
        var unmet = false
        let ids = HashSet<String>()
        for (id in m.preferences.wantedDishIds) {
            if (ids.contains(id)) {
                continue
            };
            ids.add(id)
            var met = false
            for (di in 0..dishQ.size) {
                if (dishQ[di] > 0 && f.dishes[di].id == id && f.fit[di][mi].status == "fit") {
                    met = true
                }
            }
            if (!met) {
                unmet = true
                wishes.add(
                    UnmetWish(memberId: m.id, itemId: id, itemType: "dish",
                        reason: "未入选、不可售、不适配或超出本次结构/预算"))
            }
        }
        let extraIds = ArrayList<String>()
        let seenExtraIds = HashSet<String>()
        for (wish in o.wantedExtras) {
            if (!seenExtraIds.contains(wish.dishId)) {
                seenExtraIds.add(wish.dishId)
                extraIds.add(wish.dishId)
            }
        }
        for (id in o.wantedExtraIds) {
            if (!seenExtraIds.contains(id)) {
                seenExtraIds.add(id)
                extraIds.add(id)
            }
        }
        for (id in extraIds) {
            let ownNeed = mealExtraQuantity(o, id)
            var selected: Int64 = 0
            var suitable = false
            var dishIndex: Int64 = -1
            for (di in 0..dishQ.size) {
                if (f.dishes[di].id == id) {
                    dishIndex = di
                    selected = dishQ[di]
                    suitable = f.fit[di][mi].status == "fit"
                }
            }
            var tableNeed: Int64 = 0
            if (dishIndex >= 0) {
                for (otherIndex in 0..f.members.size) {
                    if (f.fit[dishIndex][otherIndex].status == "fit") {
                        tableNeed = checkedAdd(tableNeed,
                            mealExtraQuantity(mealOptions(f.r, f.members[otherIndex].id), id))
                    }
                }
            } else {
                tableNeed = ownNeed
            }
            if (!suitable || selected < tableNeed) {
                unmet = true
                wishes.add(
                    UnmetWish(memberId: m.id, itemId: id, itemType: "dish",
                        reason: if (!suitable) {
                            "希望${ownNeed}份；该菜不可售、资料不足或不适配本人"
                        } else {
                            "希望${ownNeed}份；适配成员合计需${tableNeed}份，未全部入选或超出预算"
                        }))
            }
        }
        for (id in m.preferences.wantedSetMealIds) {
            var met = false
            for (ci in 0..q.size) {
                if (q[ci] > 0 && f.candidates[ci].item.itemType == "setMeal" && f.candidates[ci].item.itemId == id &&
                    f.candidates[ci].components.any({di => f.fit[di][mi].status == "fit"})) {
                    met = true
                }
            }
            if (!met) {
                unmet = true
                wishes.add(UnmetWish(memberId: m.id, itemId: id, itemType: "setMeal", reason: "套餐未入选或没有适配组分"))
            }
        }
        let ingredients = HashSet<String>()
        for (w in o.wantedIngredients) {
            if (ingredients.contains(w)) {
                continue
            };
            ingredients.add(w)
            var met = false
            for (di in 0..dishQ.size) {
                if (dishQ[di] > 0 && f.fit[di][mi].status == "fit" && f
                    .meta[di]
                    .primaryIngredients
                    .any({i => f.dishes[di].ingredients.contains(i) && ingredientMatches(i, w, IngredientAssociations())})) {
                    met = true
                }
            }
            if (!met) {
                unmet = true
                wishes.add(
                    UnmetWish(memberId: m.id, itemId: w, itemType: "ingredient",
                        reason: "未选到适合本人且有已核对主料匹配的菜"))
            }
        }
        if (let Some(level) <- o.wantedSpiceLevel) {
            var met = false
            for (di in 0..dishQ.size) {
                if (dishQ[di] > 0 && f.dishes[di].spiceLevel == level && f.fit[di][mi].status == "fit") {
                    met = true
                }
            }
            if (!met) {
                unmet = true
                wishes.add(
                    UnmetWish(memberId: m.id, itemId: "spice-${level}", itemType: "spice",
                        reason: "未找到适合本人且达到所选辣度的菜"))
            }
        }
        if (unmet) {
            wishPeople++
        }
    }
    var budgetGap: Int64 = 0
    var budgetBandMiss: Int64 = 0
    if (let Some(b) <- f.budget) {
        budgetGap = b - cost
        if (cost < b - b / 10) {
            budgetBandMiss = 1
        }
    }
    let vegGap = if (vegetables == 0) {
        1
    } else {
        0
    }
    let extra = if (hot > f.hotNeed) {
        hot - f.hotNeed
    } else {
        0
    }
    let repeated = hot - distinct
    var autoExtraPortions: Int64 = 0
    var autoExtraRepeated: Int64 = 0
    // Prefer sharing the order across different dishes instead of padding the
    // budget with many copies of one item.  A solo diner may still receive one
    // portion, and an explicitly requested extra quantity remains authoritative.
    let preferredDishQuantity = if (f.input.people > 1) {
        f.input.people - 1
    } else {
        1
    }
    var dishQuantityExcess: Int64 = 0
    var maxDishQuantityExcess: Int64 = 0
    for (di in 0..dishQ.size) {
        let role = f.meta[di].role
        if (role != "staple") {
            let explicitQuantity = if (role == "side" || role == "drink" || role == "coldMain") {
                mealExplicitExtraNeed(f, di)
            } else {
                0
            }
            let preferred = if (explicitQuantity > preferredDishQuantity) {
                explicitQuantity
            } else {
                preferredDishQuantity
            }
            if (dishQ[di] > preferred) {
                let excess = dishQ[di] - preferred
                dishQuantityExcess += excess
                if (excess > maxDishQuantityExcess) {
                    maxDishQuantityExcess = excess
                }
            }
        }
        if (role == "side" || role == "drink" || role == "coldMain") {
            let automatic = dishQ[di] - mealExplicitExtraNeed(f, di)
            if (automatic > 0) {
                autoExtraPortions += automatic
                if (automatic > 1) {
                    autoExtraRepeated += automatic - 1
                }
            }
        }
    }
    var tasteGain: Int64 = 0
    for (mi in 0..f.members.size) {
        for (t in f.members[mi].preferences.tastePreferences) {
            var met = false
            for (di in 0..dishQ.size) {
                if (dishQ[di] > 0 && f.fit[di][mi].status == "fit" && (f.dishes[di].taste.contains(t) ||
                    f.dishes[di].name.contains(t))) {
                    met = true
                }
            }
            if (met) {
                tasteGain++
            }
        }
    }
    let score = [if (deficits.isEmpty()) {
        0
    } else {
        1
    }, zero, allocationGap, deficits.size, hotGap, wishPeople, wishes.size, choiceGap, vegGap, budgetBandMiss,
        maxDishQuantityExcess, dishQuantityExcess, budgetGap, autoExtraRepeated, autoExtraPortions, extra, repeated,
        -tasteGain, cost]
    Some(MealState(q.clone(), dishQ, cost, score, hot, coverage, allocated, stapleIds, deficits.toArray(),
        wishes.toArray()))
}

func mealItems(f: MealFacts, s: MealState): Array<RecommendationItem> {
    let items = ArrayList<RecommendationItem>()
    let included = Array<Int64>(f.dishes.size, repeat: 0)
    for (ci in 0..s.q.size) {
        if (s.q[ci] <= 0) {
            continue
        };
        let c = f.candidates[ci]
        items.add(RecommendationItem(itemType: c.item.itemType, itemId: c.item.itemId, quantity: s.q[ci]))
        for (j in 0..c.components.size) {
            included[c.components[j]] += c.componentQuantities[j] * s.q[ci]
        }
    }
    for (di in 0..included.size) {
        if (s.dishQ[di] > included[di]) {
            items.add(RecommendationItem(itemId: f.dishes[di].id, quantity: s.dishQ[di] - included[di]))
        }
    }
    items.toArray()
}

func mealDraft(f: MealFacts, s: MealState, supplied!: ?RecommendationDraft = None): RecommendationDraft {
    let draft = supplied ?? validateRecommendation(f.input, mealItems(f, s)).unwrap()
    draft.mealStatus = if (s.complete) { "complete" } else { "partial" }
    draft.estimatedHotNeed = f.hotNeed
    draft.estimatedHotSupply = s.hot
    let portions = ArrayList<Array<MealDishPortion>>()
    mealAllocate(f, s.dishQ, portions: Some(portions))
    let pending = f.input.members.filter({m => !m.submitted})
    let allocations = ArrayList<MealAllocation>()
    for (mi in 0..f.members.size) {
        allocations.add(MealAllocation(memberId: f.members[mi].id, coverage: s.coverage[mi],
            halfDishNeed: f.halfNeeds[mi], halfDishAllocated: s.allocated[mi], hotDishes: portions[mi],
            stapleDishId: if (s.stapleIds[mi].isEmpty()) { None } else { Some(s.stapleIds[mi]) },
            stapleOptOut: f.stapleChoice[mi] == -2))
    }
    if (f.input.people > f.members.size) {
        // Split the existing reserve flow, rather than allocating the same hot
        // serving twice. Unsubmitted people use normal appetite until confirmed.
        let pool = portions[f.members.size]
        let remaining = pool.map({p => p.halfDishUnits})
        for (pi in 0..(f.input.people - f.members.size)) {
            let mi = f.members.size + pi
            let dishes = ArrayList<MealDishPortion>()
            var allocated: Int64 = 0
            for (di in 0..pool.size) {
                let units = if (remaining[di] < 2 - allocated) { remaining[di] } else { 2 - allocated }
                if (units > 0) {
                    dishes.add(MealDishPortion(dishId: pool[di].dishId, halfDishUnits: units))
                    remaining[di] -= units
                    allocated += units
                }
                if (allocated == 2) { break }
            }
            allocations.add(MealAllocation(memberId: if (pi < pending.size) {
                    pending[pi].id
                } else { "pending:${pi - pending.size}" },
                coverage: dishes.size, halfDishNeed: 2, halfDishAllocated: allocated,
                hotDishes: dishes.toArray(), provisional: true,
                stapleDishId: if (s.stapleIds[mi].isEmpty()) { None } else { Some(s.stapleIds[mi]) }))
        }
    }
    draft.mealMembers = allocations.toArray()
    draft.fits = draft.fits.filter(
        {
            entry =>
                for (di in 0..f.dishes.size) {
                    if (f.dishes[di].id == entry.dishId) {
                        for (mi in 0..f.members.size) {
                            if (f.members[mi].id == entry.memberId) {
                                return f.fit[di][mi].status == "fit"
                            }
                        }
                    }
                };
                false
        }
    )
    draft.uncoveredIds = f.members.filter(
        {
            m =>
                for (mi in 0..f.members.size) {
                    if (f.members[mi].id == m.id) {
                        return s.coverage[mi] == 0
                    }
                };
                false
        }
    ).map({m => m.id})
    draft.undercoveredIds = f.members.filter(
        {
            m =>
                for (mi in 0..f.members.size) {
                    if (f.members[mi].id == m.id) {
                        return s.coverage[mi] == 1
                    }
                };
                false
        }
    ).map({m => m.id})
    draft.unmetWishes = s.wishes
    var hasAutoExtras = false
    for (di in 0..s.dishQ.size) {
        let role = f.meta[di].role
        if ((role == "side" || role == "drink" || role == "coldMain") && s.dishQ[di] > mealExplicitExtraNeed(f, di)) {
            hasAutoExtras = true
        }
    }
    draft.notices = draft
        .notices
        .concat(s.deficits)
        .concat(if (hasAutoExtras) {
            ["为接近预算档位，已自动加入适配的小吃或饮料；明确填写的额外项数量仍按原数量处理。"]
        } else {
            []
        })
        .concat(if (f.input.people > f.members.size) {
            ["未填写成员按正常饭量预分配，饮食要求待确认，填写后将重新校验搭配。"]
        } else { [] })
        .concat(["份量按点菜习惯估算，可按实际饭量调整。"])
    draft
}

public class MealReport {
    public let draft: RecommendationDraft
    public let status: String
    public let targetBandReached: Bool
    public let hotNeed: Int64
    public let hotSupply: Int64
    public let objective: Array<Int64>
    public let deficits: Array<String>
    public let members: JsonArray
    public var expansions: Int64 = 0
    public var stopReason: String = "exhausted"
    public var elapsedMillis: Int64 = 0
    public init(draft: RecommendationDraft, status: String, targetBandReached: Bool, hotNeed: Int64, hotSupply: Int64,
        objective: Array<Int64>, deficits: Array<String>, members: JsonArray) {
        this.draft = draft
        this.status = status
        this.targetBandReached = targetBandReached
        this.hotNeed = hotNeed
        this.hotSupply = hotSupply
        this.objective = objective
        this.deficits = deficits
        this.members = members
    }
    public func toJson(): JsonObject {
        let o = JsonObject();
        o.put("status", JsonString(status));
        o.put("targetBandReached", JsonBool(targetBandReached))
        o.put("estimatedHotNeed", JsonInt(hotNeed));
        o.put("estimatedHotSupply", JsonInt(hotSupply))
        o.put("objective", JsonArray(objective.map({v => JsonInt(v)})));
        o.put("deficits", JsonArray(deficits.map({v => JsonString(v)})))
        o.put("members", members);
        o.put("expansions", JsonInt(expansions));
        o.put("stopReason", JsonString(stopReason))
        o.put("elapsedMillis", JsonInt(elapsedMillis));
        o.put("proof", JsonString("heuristic"));
        o
    }
}

public func buildMealRecommendation(r: MealRequest, clock!: Clock = SystemClock()): Outcome<MealReport> {
    try {
        if (r.input.people < 1 || r.input.people > 100 || r.input.members.size > r.input.people || r.width < 1 ||
            r.width > 64 || r.maxExpansions < 1 || r.maxExpansions > 50000 || r.budgetMillis < 1 || r.budgetMillis >
            10000) {
            throw IllegalArgumentException("人数或搜索参数越界")
        }
        if (submitted(r.input).isEmpty()) {
            return Outcome.Err(DomainError("NO_SUBMISSIONS", "至少一人提交后再推荐"))
        }
        if (r.options.size > r.input.members.size || r
            .options
            .any({o => !r.input.members.any({m => m.id == o.memberId})})) {
            throw IllegalArgumentException("成员选项无效")
        }
        let ids = HashSet<String>()
        for (o in r.options) {
            if (ids.contains(o.memberId) || !["default", "none", "noodles", "specified"].contains(o.stapleMode) ||
                o.wantedIngredients.size > 100 || o.wantedExtraIds.size > 100 || o.wantedExtras.size > 100) {
                throw IllegalArgumentException("成员选项无效")
            }
            ids.add(o.memberId);
            appetiteHalfUnits(o.appetite)
            let extraIds = HashSet<String>()
            for (w in o.wantedExtras) {
                if (w.dishId.isEmpty() || w.quantity < 1 || w.quantity > 100 || extraIds.contains(w.dishId)) {
                    throw IllegalArgumentException("菜品愿望份数无效")
                }
                extraIds.add(w.dishId)
            }
            if (let Some(level) <- o.wantedSpiceLevel) {
                if (level < 0 || level > 3) {
                    throw IllegalArgumentException("愿望辣度无效")
                }
            }
        }
        let deadline = Deadline(clock, r.budgetMillis);
        let start = clock.monotonicMillis()
        let f = MealFacts(r)
        let empty = Array<Int64>(f.candidates.size, repeat: 0)
        let initial = mealEvaluate(f, empty)
        if (initial.isNone()) {
            let draft = validateMealItems(r, []).unwrap()
            let report = MealReport(draft, "noCandidate", false, f.hotNeed, 0, [1],
                ["预算不足以提供所选主食；未擅自减少米饭，请提高预算或明确更改主食需求"],
                JsonArray(draft.mealMembers.map<JsonValue>({m => m.toJson()})))
            draft.mealStatus = "partial"
            draft.estimatedHotNeed = f.hotNeed
            draft.notices = draft.notices.concat(report.deficits)
            report.stopReason = "exhausted"
            report.elapsedMillis = clock.monotonicMillis() - start
            return Outcome.Ok(report)
        }
        let first = initial.getOrThrow()
        let best = Array<MealState>(1, repeat: first)
        var expansions: Int64 = 0;
        var stopReason = "exhausted"
        // Quickly construct a feasible seed before a broad search can spend the whole budget on partial states.
        var seed = first
        let seen = HashSet<String>();
        seen.add(mealStateKey(empty))
        let searchSteps = mealSearchSteps(f)
        for (_ in 0..searchSteps) {
            if (deadline.remainingMillis() <= 0 || expansions >= r.maxExpansions) {
                break
            }
            var next: ?MealState = None
            for (ci in 0..f.candidates.size) {
                if (deadline.remainingMillis() <= 0 || expansions >= r.maxExpansions) {
                    break
                }
                let c = f.candidates[ci]
                if (!seed.complete && c.kind != "hot") {
                    continue
                }
                for (quantity in mealCandidateNext(c, seed.q[ci])) {
                    if (deadline.remainingMillis() <= 0 || expansions >= r.maxExpansions) { break }
                    let q = seed.q.clone();
                    q[ci] = quantity
                    expansions++
                    if (let Some(s) <- mealEvaluate(f, q)) {
                        if (mealStateOrder(s, best[0]) == Ordering.LT) {
                            best[0] = s
                        }
                        if (next.isNone() || mealStateOrder(s, next.getOrThrow()) == Ordering.LT) {
                            next = Some(s)
                        }
                    }
                }
            }
            if (let Some(s) <- next) {
                if (mealStateOrder(s, seed) != Ordering.LT) {
                    break
                };
                seed = s
            } else {
                break
            }
        }
        var beam = [first, seed]
        for (_ in 0..searchSteps) {
            let next = ArrayList<MealState>()
            for (state in beam) {
                for (ci in 0..f.candidates.size) {
                    if (deadline.remainingMillis() <= 0 || expansions >= r.maxExpansions) {
                        break
                    }
                    let c = f.candidates[ci]
                    if (!state.complete && c.kind != "hot") {
                        continue
                    }
                    for (quantity in mealCandidateNext(c, state.q[ci])) {
                        if (deadline.remainingMillis() <= 0 || expansions >= r.maxExpansions) { break }
                        let q = state.q.clone();
                        q[ci] = quantity
                        let key = mealStateKey(q);
                        if (seen.contains(key)) {
                            continue
                        };
                        seen.add(key)
                        expansions++
                        if (let Some(s) <- mealEvaluate(f, q)) {
                            if (mealStateOrder(s, best[0]) == Ordering.LT) {
                                best[0] = s
                            };
                            next.add(s)
                        }
                    }
                }
                if (deadline.remainingMillis() <= 0 || expansions >= r.maxExpansions) {
                    break
                }
            }
            if (deadline.remainingMillis() <= 0) {
                stopReason = "deadline"
                break
            }
            if (expansions >= r.maxExpansions) {
                stopReason = "expansionLimit"
                break
            }
            if (next.isEmpty()) {
                break
            }
            let ranked = next.toArray();
            sort(ranked, by: mealStateOrder)
            let kept = ArrayList<MealState>();
            let buckets = HashMap<String, Int64>()
            // Keep several cost bands and coverage patterns, then fill spare slots by full rank.
            for (s in ranked) {
                let band = match (f.budget) {
                    case Some(b) =>
                        if (b > 0) {
                            s.cost / (b / 10 + 1)
                        } else {
                            0
                        };
                    case None => s.cost / 1000
                }
                let bucket = "${s.complete}:${s.hot}:${band}:${s.coverage.map({ v => if (v > 1) { 2 } else { v } })}"
                let used = buckets.get(bucket) ?? 0
                if (used < 2 && kept.size < r.width) {
                    kept.add(s);
                    buckets[bucket] = used + 1
                }
            }
            for (s in ranked) {
                if (kept.size >= r.width) {
                    break
                };
                if (!kept.any({k => mealStateKey(k.q) == mealStateKey(s.q)})) {
                    kept.add(s)
                }
            }
            beam = kept.toArray()
        }
        // Bounded one-for-one replacements allow cheaper seeds to approach the budget band.
        for (_ in 0..3) {
            let origin = best[0]
            for (remove in 0..f.candidates.size) {
                if (origin.q[remove] <= 0) {
                    continue
                }
                for (add in 0..f.candidates.size) {
                    if (deadline.remainingMillis() <= 0 || expansions >= r.maxExpansions) {
                        break
                    }
                    if (remove == add) {
                        continue
                    }
                    let q = origin.q.clone()
                    q[remove] -= f.candidates[remove].step
                    q[add] += f.candidates[add].step
                    if (q[add] > f.candidates[add].limit) {
                        continue
                    }
                    let key = mealStateKey(q);
                    if (seen.contains(key)) {
                        continue
                    };
                    seen.add(key)
                    expansions++
                    if (let Some(s) <- mealEvaluate(f, q)) {
                        if (mealStateOrder(s, best[0]) == Ordering.LT) {
                            best[0] = s
                        }
                    }
                }
            }
            if (mealStateKey(origin.q) == mealStateKey(best[0].q)) {
                break
            }
        }
        if (stopReason == "exhausted" && deadline.remainingMillis() <= 0) {
            stopReason = "deadline"
        }
        if (stopReason == "exhausted" && expansions >= r.maxExpansions) {
            stopReason = "expansionLimit"
        }
        let s = best[0];
        let draft = mealDraft(f, s)
        let rows = draft.mealMembers.map<JsonValue>({m => m.toJson()})
        let reached = match (f.budget) {
            case Some(b) => s.cost >= b - b / 10 && s.cost <= b;
            case None => false
        }
        let report = MealReport(draft, if (s.complete) {
            "complete"
        } else {
            "partial"
        }, reached, f.hotNeed, s.hot, s.score, s.deficits, JsonArray(rows))
        report.expansions = expansions
        report.stopReason = stopReason
        report.elapsedMillis = clock.monotonicMillis() - start
        return Outcome.Ok(report)
    } catch (e: IllegalArgumentException) {
        return Outcome.Err(DomainError("INVALID_MEAL_REQUEST", e.message))
    }
}

public func inspectMealMenu(r: MealRequest): JsonArray {
    let f = MealFacts(r);
    let rows = ArrayList<JsonValue>()
    for (di in 0..f.dishes.size) {
        let row = JsonObject();
        row.put("dishId", JsonString(f.dishes[di].id));
        row.put("tableExcluded", JsonBool(f.excluded[di]))
        let fits = ArrayList<JsonValue>()
        for (mi in 0..f.members.size) {
            let fit = f.fit[di][mi];
            let v = JsonObject();
            v.put("memberId", JsonString(f.members[mi].id));
            v.put("status", JsonString(fit.status))
            v.put("reasons", JsonArray(fit.reasons.map({s => JsonString(s)})));
            fits.add(v)
        }
        row.put("fits", JsonArray(fits.toArray()));
        rows.add(row)
    }
    JsonArray(rows.toArray())
}

// Validate exactly the submitted items. Manual edits never silently restore removed rice or dishes.
public func validateMealItems(r: MealRequest, items: Array<RecommendationItem>): Outcome<RecommendationDraft> {
    try {
        let f = MealFacts(r)
        let validated = validateRecommendation(f.input, items)
        if (let Err(e) <- validated) { return Outcome.Err(e) }
        let expansion = expandItems(f.input.menu, items).unwrap()
        for (d in expansion.dishes) {
            if (d.quantity > 100 || !f.meta.any({m => m.dishId == d.dish.id && m.role != "unknown"})) {
                return Outcome.Err(DomainError("INVALID_MEAL", "菜品角色未确认或份数超限"))
            }
        }
        let state = mealEvaluate(f, Array<Int64>(f.candidates.size, repeat: 0), manual: Some(expansion))
        if (state.isNone()) { return Outcome.Err(DomainError("INVALID_MEAL", "超出预算或本桌菜量上限")) }
        Outcome.Ok(mealDraft(f, state.getOrThrow(), supplied: Some(validated.unwrap())))
    } catch (e: IllegalArgumentException) { Outcome.Err(DomainError("INVALID_MEAL", e.message)) }
}
