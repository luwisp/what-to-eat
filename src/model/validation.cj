package huaiwei.model

import std.collection.*

public func validateDishInput(input: DishInput): Outcome<Unit> {
    if (input.name.trimAscii().isEmpty() || input.priceFen < 0) {
        return Outcome.Err(DomainError("INVALID_DISH", "请填写菜名和非负价格"))
    }
    let categories = ["cold", "hot", "soup", "staple", "drink"]
    if (!categories.contains(input.category)) {
        return Outcome.Err(DomainError("INVALID_CATEGORY", "菜品分类无效"))
    }
    return validateSpice(input.spiceLevel)
}

public func validateSetMealInput(input: SetMealInput): Outcome<Unit> {
    if (input.name.trimAscii().isEmpty() || input.priceFen < 0 || input.components.isEmpty()) {
        return Outcome.Err(DomainError("INVALID_SET_MEAL", "套餐须有名称、非负价格和组分"))
    }
    for (component in input.components) {
        if (component.dishId.trimAscii().isEmpty() || !validateQuantity(component.quantity).isOk()) {
            return Outcome.Err(DomainError("INVALID_COMPONENT", "套餐组分须指定菜品和正整数份数"))
        }
    }
    return Outcome.Ok(())
}

public func normalizeIngredients(values: Array<String>): Array<String> {
    let result = ArrayList<String>()
    for (raw in values) {
        let clean = raw.trimAscii()
        if (clean.isEmpty()) { continue }
        let normalized = if (clean.toAsciiLower() == "unknown") { "unknown" } else { clean }
        if (!result.contains(normalized)) { result.add(normalized) }
    }
    if (result.isEmpty()) { result.add("unknown") }
    return result.toArray()
}

// Parse decimal yuan without any floating-point conversion, including overflow.
public func parsePriceFen(value: String): Outcome<Int64> {
    let invalid = Outcome<Int64>.Err(DomainError("INVALID_PRICE", "价格须为非负金额，最多两位小数"))
    let text = value.trimAscii()
    if (text.isEmpty()) { return invalid }
    var result: Int64 = 0
    var decimals: Int64 = -1
    var digits: Int64 = 0
    for (byte in text.toArray()) {
        if (byte == b'.') {
            if (decimals >= 0 || digits == 0) { return invalid }
            decimals = 0
            continue
        }
        if (byte < b'0' || byte > b'9') { return invalid }
        let digit = Int64(byte - b'0')
        if (result > (Int64.Max - digit) / 10) { return invalid }
        result = result * 10 + digit
        digits++
        if (decimals >= 0) {
            decimals++
            if (decimals > 2) { return invalid }
        }
    }
    if (decimals == 0) { return invalid }
    let multiplier: Int64 = if (decimals == -1) { 100 } else if (decimals == 1) { 10 } else { 1 }
    if (result > Int64.Max / multiplier) { return invalid }
    return Outcome.Ok(result * multiplier)
}

public func validateSpice(value: Int64): Outcome<Unit> {
    if (value < 0 || value > 3) { return Outcome.Err(DomainError("INVALID_SPICE", "辣度须为0至3")) }
    return Outcome.Ok(())
}

public func validateQuantity(value: Int64): Outcome<Unit> {
    if (value <= 0) { return Outcome.Err(DomainError("INVALID_QUANTITY", "份数须为正整数")) }
    return Outcome.Ok(())
}
