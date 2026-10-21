// Decode an exported importer snapshot with the application's actual model.
import std.env.*
import std.fs.*
import std.io.*
import juxiaobao.model.*
import stdx.encoding.json.*

main(): Int64 {
    let args = getCommandLine()
    if (args.size != 2) { throw Exception("Expected snapshot JSON path") }
    try (file = File(args[1], Read)) {
        let snapshot = DatabaseSnapshot.fromJson(JsonValue.fromStr(String.fromUtf8(readToEnd(file))).asObject())
        if (snapshot.restaurants.size != 1 || snapshot.dishes.size != 84 || snapshot.menuVersions[0].menuVersion != 1) {
            throw Exception("Unexpected imported catalog")
        }
        for (dish in snapshot.dishes) {
            if (!validateDishInput(DishInput(name: dish.name, priceFen: dish.priceFen, category: dish.category,
                ingredients: dish.ingredients, spiceLevel: dish.spiceLevel)).isOk()) {
                throw Exception("Imported dish violates application validation")
            }
        }
        println("Cangjie DatabaseSnapshot decode and dish validation: 84 PASS")
    }
    return 0
}
