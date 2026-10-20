package huaiwei.agent

import huaiwei.model.*
import stdx.encoding.json.*

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

public class ToolRegistry {
    public func execute(input: RuleInput, name: String, args: JsonObject): Outcome<JsonValue> {
        try {
            match (name) {
                case "search_menu" =>
                    let query = args["query"].asString().getValue()
                    return Outcome.Ok(
                        JsonArray(
                            input.menu.dishes.filter({d => d.name.contains(query)}).map<JsonValue>({d => d.toJson()})))
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
        "{\"type\":\"function\",\"function\":{\"name\":\"search_menu\",\"description\":\"搜索当前餐馆的菜品事实\",\"parameters\":{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\"}},\"required\":[\"query\"]}}}",
        "{\"type\":\"function\",\"function\":{\"name\":\"get_dish\",\"description\":\"查询同店菜品和原始食材\",\"parameters\":{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"string\"}},\"required\":[\"id\"]}}}",
        "{\"type\":\"function\",\"function\":{\"name\":\"get_set_meal\",\"description\":\"查询同店固定套餐组分\",\"parameters\":{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"string\"}},\"required\":[\"id\"]}}}",
        "{\"type\":\"function\",\"function\":{\"name\":\"propose_items\",\"description\":\"提出必须经过服务器校验的组合\",\"parameters\":{\"type\":\"object\",\"properties\":{\"items\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{\"itemType\":{\"type\":\"string\",\"enum\":[\"dish\",\"setMeal\"]},\"itemId\":{\"type\":\"string\"},\"quantity\":{\"type\":\"integer\",\"minimum\":1}},\"required\":[\"itemType\",\"itemId\",\"quantity\"]}}},\"required\":[\"items\"]}}}"
    ]
    templates.map({text => JsonValue.fromStr(text).asObject()})
}
