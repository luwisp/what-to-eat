package juxiaobao.model

import std.unittest.*
import std.unittest.testmacro.*

@Test
class ValidationTests {
    @TestCase
    func ingredientsPreserveKnownAndUnknown() {
        @Expect(normalizeIngredients([" 土豆 ", " UNKNOWN ", "unknown", "青椒"]), ["土豆", "unknown", "青椒"])
        @Expect(normalizeIngredients([]), ["unknown"])
        @Expect(normalizeIngredients([" ", "\t"]), ["unknown"])
    }

    @TestCase
    func pricesUseExactCents() {
        @Expect(parsePriceFen("19.90").unwrap(), 1990)
        @Expect(parsePriceFen("0.01").unwrap(), 1)
        @Expect(parsePriceFen("12").unwrap(), 1200)
        @Expect(parsePriceFen("12.3").unwrap(), 1230)
        for (value in ["-1", "1.001", "1e2", "NaN", "", ".50", "1.", "92233720368547758.08"]) {
            @Expect(parsePriceFen(value).isOk(), false)
        }
    }

    @TestCase
    func spiceAndQuantityAreBounded() {
        @Expect(validateSpice(4).isOk(), false)
        @Expect(validateSpice(-1).isOk(), false)
        @Expect(validateSpice(0).isOk(), true)
        @Expect(validateQuantity(0).isOk(), false)
        @Expect(validateQuantity(1).isOk(), true)
    }

    @TestCase
    func invalidDishAndEmptySetMealRejected() {
        @Expect(validateDishInput(DishInput(name: "菜", priceFen: -1)).isOk(), false)
        @Expect(validateDishInput(DishInput(name: "菜", category: "setMeal")).isOk(), false)
        @Expect(validateDishInput(DishInput(name: "菜", spiceLevel: 4)).isOk(), false)
        @Expect(validateSetMealInput(SetMealInput(name: "套餐")).isOk(), false)
        @Expect(validateSetMealInput(SetMealInput(name: "套餐", components: [SetMealComponent(dishId: "d", quantity: 0)])).isOk(), false)
        @Expect(validateDishInput(DishInput(name: "土豆", ingredients: ["土豆", "unknown"])).isOk(), true)
    }
}
