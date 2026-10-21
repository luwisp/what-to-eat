package juxiaobao.agent

import juxiaobao.model.*
import stdx.encoding.json.*
import std.collection.*

public func parseProposedItems(value: JsonValue): Array<RecommendationItem> {
    let items = value.asArray().getItems().toArray()
    if (items.size > 100) {
        throw IllegalArgumentException("Too many items")
    }
    return items.map(
        {
            v =>
                let o = v.asObject()
                // Prices, recipes, dish names and fits are always recomputed locally.
                RecommendationItem(itemType: o["itemType"].asString().getValue(),
                    itemId: o["itemId"].asString().getValue(), quantity: o["quantity"].asInt().getValue())
        }
    )
}

public func validateAssociations(menu: MenuSnapshot, associations: IngredientAssociations): Bool {
    if (associations.entries.size > 100) {
        return false
    }
    for (entry in associations.entries) {
        if (entry.ingredient.trimAscii().toAsciiLower() == "unknown" || entry.related.size > 30) {
            return false
        }
        var known = false
        for (dish in menu.dishes) {
            if (dish.ingredients.contains(entry.ingredient)) {
                known = true
            }
        }
        if (!known) {
            return false
        }
        for (name in entry.related) {
            if (name.isEmpty() || name.size > 128 || name.toAsciiLower() == "unknown") {
                return false
            }
        }
    }
    return true
}

// Discovery is bounded to available dishes in this restaurant. Full recipes remain
// available through get_dish; the search result is deliberately compact.
func searchMenu(input: RuleInput, args: JsonObject): JsonArray {
    let query = match (args.get("query")) {
        case Some(v) => v.asString().getValue().trimAscii();
        case None => ""
    }
    let signature = match (args.get("signatureOnly")) {
        case Some(v) => v.asBool().getValue();
        case None => false
    }
    let taste = match (args.get("taste")) {
        case Some(v) => v.asString().getValue();
        case None => ""
    }
    let method = match (args.get("cookingMethod")) {
        case Some(v) => v.asString().getValue();
        case None => ""
    }
    let category = match (args.get("category")) {
        case Some(v) => v.asString().getValue();
        case None => ""
    }
    let maxSpice = match (args.get("maxSpiceLevel")) {
        case Some(v) => v.asInt().getValue();
        case None => 3
    }
    let maxPrice = match (args.get("maxPriceFen")) {
        case Some(v) => v.asInt().getValue();
        case None => Int64.Max
    }
    let results = ArrayList<JsonValue>()
    for (d in input.menu.dishes) {
        if (results.size >= 12) {
            break
        }
        if (!d.available || d.restaurantId != input.menu.restaurant.id || (signature && !d.isSignature) ||
            !d.taste.contains(taste) || !d.cookingMethod.contains(method) || (!category.isEmpty() && d.category !=
            category) || d.spiceLevel > maxSpice || d.priceFen > maxPrice) {
            continue
        }
        if (!query.isEmpty() && !d.name.contains(query) && !d.description.contains(query) && !d.taste.contains(query) &&
            !d.cookingMethod.contains(query) && !d.ingredients.any({i => i.contains(query)})) {
            continue
        }
        let fact = JsonObject()
        fact.put("id", JsonString(d.id));
        fact.put("name", JsonString(d.name))
        fact.put("priceFen", JsonInt(d.priceFen));
        fact.put("taste", JsonString(d.taste))
        fact.put("cookingMethod", JsonString(d.cookingMethod));
        fact.put("category", JsonString(d.category))
        fact.put("spiceLevel", JsonInt(d.spiceLevel));
        fact.put("isSignature", JsonBool(d.isSignature))
        results.add(fact)
    }
    JsonArray(results.toArray())
}

func editPlan(input: RuleInput, args: JsonObject): Outcome<JsonValue> {
    let operations = args["operations"].asArray().getItems().toArray()
    if (operations.isEmpty() || operations.size > 20) {
        return Outcome.Err(DomainError("INVALID_TOOL_INPUT", "每次可调整1到20项"))
    }
    var items = input.baseItems.map({i => RecommendationItem.fromJson(i.toJson())})
    for (raw in operations) {
        let o = raw.asObject()
        let kind = o["itemType"].asString().getValue()
        let id = o["itemId"].asString().getValue()
        let action = o["action"].asString().getValue()
        let known = if (kind == "dish") {
            input.menu.dishes.any({d => d.id == id && d.restaurantId == input.menu.restaurant.id})
        } else if (kind == "setMeal") {
            input.menu.setMeals.any({m => m.id == id && m.restaurantId == input.menu.restaurant.id})
        } else {
            false
        }
        if (!known) {
            return Outcome.Err(DomainError("NOT_FOUND", "当前餐馆没有该条目"))
        }
        let previous = items.filter({i => i.itemType == kind && i.itemId == id})
        var quantity: Int64 = 0
        if (action == "remove") {
            if (previous.isEmpty()) {
                return Outcome.Err(DomainError("INVALID_TOOL_INPUT", "方案中没有这道菜"))
            }
        } else if (action == "add" || action == "setQuantity") {
            let value = o["quantity"].asInt().getValue()
            if (value < 1 || value > 100) {
                return Outcome.Err(DomainError("INVALID_TOOL_INPUT", "份数应为1到100的整数"))
            }
            quantity = value + if (action == "add" && !previous.isEmpty()) {
                previous[0].quantity
            } else {
                0
            }
            if (quantity > 100) {
                return Outcome.Err(DomainError("INVALID_TOOL_INPUT", "份数超过上限"))
            }
        } else {
            return Outcome.Err(DomainError("INVALID_TOOL_INPUT", "不支持的方案操作"))
        }
        if (quantity == 0) {
            items = items.filter({i => i.itemType != kind || i.itemId != id})
        } else {
            let changed = RecommendationItem(itemType: kind, itemId: id, quantity: quantity)
            items = if (previous.isEmpty()) {
                items.concat([changed])
            } else {
                items.map({
                    i => if (i.itemType == kind && i.itemId == id) {
                    changed
                } else {
                    i
                }
                })
            }
        }
    }
    match (checkMealRecommendation(input, items)) {
        case Ok(draft) => Outcome.Ok(draft.toJson());
        case Err(e) => Outcome.Err(e)
    }
}

public class ToolRegistry {
    public func execute(input: RuleInput, name: String, args: JsonObject): Outcome<JsonValue> {
        try {
            match (name) {
                case "search_menu" => return Outcome.Ok(searchMenu(input, args))
                case "edit_plan" => return editPlan(input, args)
                case "get_dish" =>
                    let id = args["id"].asString().getValue()
                    for (d in input.menu.dishes) {
                        if (d.id == id && d.restaurantId == input.menu.restaurant.id) {
                            return Outcome.Ok(d.toJson())
                        }
                    }
                case "get_set_meal" =>
                    let id = args["id"].asString().getValue()
                    for (m in input.menu.setMeals) {
                        if (m.id == id && m.restaurantId == input.menu.restaurant.id) {
                            return Outcome.Ok(m.toJson())
                        }
                    }
                case "propose_items" =>
                    let result = checkMealRecommendation(input, parseProposedItems(args["items"]))
                    match (result) {
                        case Ok(draft) => return Outcome.Ok(draft.toJson());
                        case Err(e) => return Outcome.Err(e)
                    }
                case _ => return Outcome.Err(DomainError("TOOL_FORBIDDEN", "模型不能修改要求、权限或访问任意URL"))
            }
            return Outcome.Err(DomainError("NOT_FOUND", "当前餐馆没有该条目", status: 404))
        } catch (_: Exception) {
            Outcome.Err(DomainError("INVALID_TOOL_INPUT", "工具参数无效"))
        }
    }
}

public func diningToolDefinitions(): Array<JsonObject> {
    let templates = [
        "{\"type\":\"function\",\"function\":{\"name\":\"search_menu\",\"description\":\"主动查找本店招牌、口味、做法、食材等特征。仅返回可售菜，最多12项；可用get_dish查看完整资料。\",\"parameters\":{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\"},\"signatureOnly\":{\"type\":\"boolean\"},\"taste\":{\"type\":\"string\"},\"cookingMethod\":{\"type\":\"string\"},\"category\":{\"type\":\"string\"},\"maxSpiceLevel\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":3},\"maxPriceFen\":{\"type\":\"integer\",\"minimum\":0}},\"required\":[],\"additionalProperties\":false}}}",
        "{\"type\":\"function\",\"function\":{\"name\":\"get_dish\",\"description\":\"查询同店菜品和原始食材\",\"parameters\":{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"string\"}},\"required\":[\"id\"],\"additionalProperties\":false}}}",
        "{\"type\":\"function\",\"function\":{\"name\":\"get_set_meal\",\"description\":\"查询同店固定套餐组分\",\"parameters\":{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"string\"}},\"required\":[\"id\"],\"additionalProperties\":false}}}",
        "{\"type\":\"function\",\"function\":{\"name\":\"propose_items\",\"description\":\"提出必须经过服务器校验的整桌方案\",\"parameters\":{\"type\":\"object\",\"properties\":{\"items\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{\"itemType\":{\"type\":\"string\",\"enum\":[\"dish\",\"setMeal\"]},\"itemId\":{\"type\":\"string\"},\"quantity\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":100}},\"required\":[\"itemType\",\"itemId\",\"quantity\"],\"additionalProperties\":false},\"maxItems\":100}},\"required\":[\"items\"],\"additionalProperties\":false}}}",
        "{\"type\":\"function\",\"function\":{\"name\":\"edit_plan\",\"description\":\"直接调整当前这桌方案：add增加份数，remove移除，setQuantity设置份数。add和setQuantity须传quantity。保留未操作条目，经服务器重新校验。不会修改商家菜品资料。\",\"parameters\":{\"type\":\"object\",\"properties\":{\"operations\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{\"itemType\":{\"type\":\"string\",\"enum\":[\"dish\",\"setMeal\"]},\"itemId\":{\"type\":\"string\"},\"quantity\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":100},\"action\":{\"type\":\"string\",\"enum\":[\"add\",\"remove\",\"setQuantity\"]}},\"required\":[\"action\",\"itemType\",\"itemId\"],\"additionalProperties\":false},\"minItems\":1,\"maxItems\":20}},\"required\":[\"operations\"],\"additionalProperties\":false}}}"
    ]
    templates.map({text => JsonValue.fromStr(text).asObject()})
}
