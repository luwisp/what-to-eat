// Local-only, read-only algorithm workbench. Never mounted by production main.
import juxiaobao.model.*
import juxiaobao.platform.*
import juxiaobao.agent.*
import juxiaobao.room.*
import std.collection.*
import std.env.*
import std.convert.*
import std.fs.*
import std.io.*
import std.database.sql.*
import std.sync.*
import std.sort.*
import stdx.encoding.json.*
import stdx.net.http.*
import sqlite4cj.*

func readMenu(path: String, code: String): MenuSnapshot {
    try (probe = File(path, Read)) {
        ()
    }
    try (ds = SqliteDatasource(path)) {
        try (cn = SqliteConnection(ds)) {
            cn.exec("PRAGMA query_only=ON")
            try (query = cn.prepareStatement("SELECT payload_json FROM app_snapshot WHERE id=1 AND schema_version=1")) {
                let rows = query.query()
                if (!rows.next()) {
                    throw Exception("Run scripts/import-menu.py first")
                }
                let snapshot = DatabaseSnapshot.fromJson(JsonValue.fromStr(rows.get<String>(0)).asObject())
                for (restaurant in snapshot.restaurants) {
                    if (restaurant.restaurantCode == code) {
                        var version: Int64 = 0
                        for (v in snapshot.menuVersions) {
                            if (v.restaurantId == restaurant.id) {
                                version = v.menuVersion
                            }
                        }
                        return MenuSnapshot(restaurant: restaurant, menuVersion: version,
                            dishes: snapshot.dishes.filter({d => d.restaurantId == restaurant.id}),
                            setMeals: snapshot.setMeals.filter({m => m.restaurantId == restaurant.id}))
                    }
                }
                throw Exception("Restaurant not found")
            }
        }
    }
    throw Exception("Unable to read menu")
}

func parseInput(body: JsonObject, menu: MenuSnapshot): RuleInput {
    let members = ArrayList<Participant>()
    for (value in body["members"].asArray().getItems()) {
        let row = value.asObject()
        let id = row["id"].asString().getValue()
        if (id.isEmpty() || members.any({m => m.id == id})) {
            throw IllegalArgumentException("Invalid member id")
        }
        let prefs = Preferences.fromJson(row["preferences"].asObject())
        checkPreferences(prefs)
        members.add(
            Participant(id: id, nickname: row["nickname"].asString().getValue(),
                submitted: row["submitted"].asBool().getValue(), preferences: prefs))
    }
    let people = body["people"].asInt().getValue()
    if (people < 1 || people > 12 || members.size < 1 || members.size > people) {
        throw IllegalArgumentException("Dev workbench supports 1-12 people")
    }
    let budget: ?Int64 = match (body["budgetPerPersonFen"]) {
        case _: JsonNull => None;
        case _ => Some(body["budgetPerPersonFen"].asInt().getValue())
    }
    if (let Some(n) <- budget) {
        if (n < 0 || n > 10000000) {
            throw IllegalArgumentException("Invalid budget")
        }
    }
    // Simulation edits affect only this detached menu; SQLite is never written.
    let unknown = body["unknownDishIds"].asArray().getItems().toArray().map({v => v.asString().getValue()})
    let unavailable = body["unavailableDishIds"].asArray().getItems().toArray().map({v => v.asString().getValue()})
    for (d in menu.dishes) {
        if (unknown.contains(d.id)) {
            d.ingredients = normalizeIngredients(d.ingredients.concat(["unknown"]))
        }
        if (unavailable.contains(d.id)) {
            d.available = false
        }
    }
    return RuleInput(menu: menu, members: members.toArray(), people: people, budgetPerPersonFen: budget)
}

func loadMealFacts(menu: MenuSnapshot): JsonObject {
    let path = getVariable("JUXIAOBAO_DEV_METADATA") ?? "data/runtime/meal-metadata.json"
    try (file = File(path, Read)) {
        let obj = JsonValue.fromStr(String.fromUtf8(readToEnd(file))).asObject()
        if (obj["restaurantId"].asString().getValue() != menu.restaurant.id || obj["menuVersion"].asInt().getValue() != menu
            .menuVersion) {
            throw IllegalArgumentException("角色事实与菜单版本不一致，请重启调试服务刷新")
        }
        return obj
    }
    throw Exception("角色事实无法读取")
}

func devMealRequest(body: JsonObject, input: RuleInput): MealRequest {
    let facts = loadMealFacts(input.menu)
    let meta = facts["dishes"].asArray().getItems().toArray().map({v => MealMetadata.fromJson(v.asObject())})
    let options = ArrayList<MealMemberOptions>()
    for (value in body["members"].asArray().getItems()) {
        let row = value.asObject()
        if (!row.containsKey("meal")) {
            continue
        }
        let m = row["meal"].asObject()
        let wantedExtraIds: Array<String> = if (m.containsKey("wantedExtraIds")) {
            m["wantedExtraIds"].asArray().getItems().toArray().map({v => v.asString().getValue()})
        } else {
            []
        }
        let wantedExtras: Array<MealExtraWish> = if (m.containsKey("wantedExtras")) {
            m["wantedExtras"]
                .asArray()
                .getItems()
                .toArray()
                .map(
                    {v =>
                        let wish = v.asObject()
                        MealExtraWish(wish["dishId"].asString().getValue(),
                            quantity: wish["quantity"].asInt().getValue())
                    })
        } else {
            []
        }
        options.add(
            MealMemberOptions(row["id"].asString().getValue(), appetite: m["appetite"].asString().getValue(),
                stapleMode: m["stapleMode"].asString().getValue(), stapleDishId: match (m["stapleDishId"]) {
                    case _: JsonNull => None;
                    case _ => Some(m["stapleDishId"].asString().getValue())
                }, confirmSingleServing: if (m.containsKey("confirmSingleServing")) {
                    m["confirmSingleServing"].asBool().getValue()
                } else {
                    false
                },
                wantedIngredients: m["wantedIngredients"]
                    .asArray()
                    .getItems()
                    .toArray()
                    .map({v => v.asString().getValue()}),
                wantedExtraIds: wantedExtraIds, wantedExtras: wantedExtras,
                wantedSpiceLevel: match (m["wantedSpiceLevel"]) {
                    case _: JsonNull => None;
                    case _ => Some(m["wantedSpiceLevel"].asInt().getValue())
                }))
    }
    return MealRequest(input, meta, options: options.toArray(), maxExpansions: body["maxExpansions"].asInt().getValue(),
        width: body["width"].asInt().getValue())
}

func devMenuJson(menu: MenuSnapshot): JsonObject {
    let result = menu.toJson();
    result.put("mealMetadata", loadMealFacts(menu)["dishes"])
    let choices = HashSet<String>()
    let hidden = ["water", "水", "盐", "食盐", "白砂糖", "白糖", "鸡精", "味精", "冰糖", "配料包", "调料包", "unknown"]
    for (d in menu.dishes) {
        if (d.available) {
            for (i in normalizeIngredients(d.ingredients)) {
                if (!hidden.contains(i) && !i.contains("配料包") && !i.contains("调料包")) {
                    choices.add(i)
                }
            }
        }
    }
    let ingredients = choices.toArray();
    sort(ingredients, by: {
        a, b => if (a < b) {
        Ordering.LT
    } else if (a > b) {
        Ordering.GT
    } else {
        Ordering.EQ
    }
    })
    result.put("ingredientOptions", JsonArray(ingredients.map({s => JsonString(s)})))
    result
}

main(): Int64 {
    let path = getVariable("JUXIAOBAO_DEV_DB") ?? "data/runtime/juxiaobao.sqlite"
    let code = getVariable("JUXIAOBAO_DEV_RESTAURANT") ?? "LAOXIANGJI"
    let port = UInt16.parse(getVariable("JUXIAOBAO_DEV_PORT") ?? "8091")
    let host = getVariable("JUXIAOBAO_DEV_HOST") ?? "127.0.0.1"
    let publicOrigin = getVariable("JUXIAOBAO_DEV_ORIGIN") ?? "http://127.0.0.1:${port}"
    let root = getVariable("JUXIAOBAO_DEV_ROOT") ?? "dev/algorithm"
    // Fail visibly at startup if the real imported menu is unavailable.
    let initial = readMenu(path, code)
    let lock = Mutex()
    let server = createHttpServer(
        ServerConfig(host, port, false),
        configure: {
            router =>
                router.on("GET", "/", {
                    ctx, _ => try (file = File(root + "/index.html", Read)) {
                        ctx
                            .responseBuilder
                            .header("content-type", "text/html; charset=utf-8")
                            .header("cache-control", "no-store")
                            .body(readToEnd(file))
                    }
                })
                router.on("GET", "/app.js", {
                    ctx, _ => try (file = File(root + "/app.js", Read)) {
                        ctx
                            .responseBuilder
                            .header("content-type", "text/javascript; charset=utf-8")
                            .header("cache-control", "no-store")
                            .body(readToEnd(file))
                    }
                })
                router.on("GET", "/api/dev/menu", {
                    ctx, _ => try {
                        jsonResponse(ctx, 200, devMenuJson(readMenu(path, code)))
                    } catch (_: Exception) {
                        jsonError(ctx, 500, "MENU_READ_FAILED", "菜单读取失败，请检查导入数据库")
                    }
                })
                router.on(
                    "POST",
                    "/api/dev/recommend",
                    {
                        ctx, _ =>
                            // Reject browser cross-site calls, including localhost services reached from an unrelated page.
                            if (let Some(origin) <- ctx.request.headers.getFirst("origin")) {
                                if (origin != "http://127.0.0.1:${port}" && origin != "http://localhost:${port}" && origin != publicOrigin) {
                                    jsonError(ctx, 403, "INVALID_ORIGIN", "仅允许已配置地址的同源请求");
                                    return
                                }
                            }
                            if (ctx.request.headers.getFirst("sec-fetch-site") == Some("cross-site")) {
                                jsonError(ctx, 403, "INVALID_ORIGIN", "仅允许已配置地址的同源请求");
                                return
                            }
                            try {
                                let body = readJsonBody(ctx)
                                let input = parseInput(body, readMenu(path, code))
                                if (body.containsKey("menuVersion") && body["menuVersion"].asInt().getValue() != input
                                    .menu
                                    .menuVersion) {
                                    jsonError(ctx, 409, "MENU_CHANGED", "菜单版本已变化，请刷新后重新选择");
                                    return
                                }
                                let count = body["maxExpansions"].asInt().getValue()
                                let width = body["width"].asInt().getValue()
                                // Serialize experiments on this small dev host; no SQLite write lock is held.
                                synchronized(lock) {
                                    let clock = SystemClock()
                                    let start = clock.monotonicMillis()
                                    let algorithm = if (body.containsKey("algorithm")) {
                                        body["algorithm"].asString().getValue()
                                    } else {
                                        "v1"
                                    }
                                    if (algorithm == "v3") {
                                        let request = devMealRequest(body, input)
                                        match (buildMealRecommendation(request, clock: clock)) {
                                            case Err(e) => jsonError(ctx, e.status, e.code, e.message)
                                            case Ok(report) =>
                                                let baseline = buildRuleRecommendation(input).unwrap()
                                                let result = JsonObject()
                                                result.put("baseline", baseline.toJson());
                                                result.put("optimized", report.draft.toJson())
                                                result.put("algorithm", JsonString("v3"));
                                                result.put("mealReport", report.toJson())
                                                result.put("baselineObjective", JsonArray([]))
                                                result.put("optimizedObjective",
                                                    JsonArray(report.objective.map({v => JsonInt(v)})))
                                                result.put("eligibility", inspectMealMenu(request));
                                                result.put("menu", devMenuJson(input.menu))
                                                result.put("menuVersion", JsonInt(input.menu.menuVersion));
                                                result.put("expansions", JsonInt(report.expansions))
                                                result.put("stoppedByDeadline", JsonBool(report.stopReason == "deadline"))
                                                result.put("stoppedByLimit",
                                                    JsonBool(report.stopReason == "expansionLimit"))
                                                result.put("elapsedMillis", JsonInt(clock.monotonicMillis() - start))
                                                jsonResponse(ctx, 200, result)
                                        }
                                        return
                                    }
                                    if (algorithm != "v1") {
                                        throw IllegalArgumentException("未知算法版本")
                                    }
                                    match (buildSearchRecommendation(input, maxExpansions: count, width: width)) {
                                        case Err(e) => jsonError(ctx, e.status, e.code, e.message)
                                        case Ok(report) =>
                                            let result = JsonObject()
                                            result.put("baseline", report.baseline.toJson())
                                            result.put("optimized", report.optimized.toJson())
                                            result.put("baselineObjective",
                                                JsonArray(
                                                    recommendationObjective(input, report.baseline).map(
                                                        {n => JsonInt(n)})))
                                            result.put("optimizedObjective",
                                                JsonArray(
                                                    recommendationObjective(input, report.optimized).map(
                                                        {n => JsonInt(n)})))
                                            result.put("eligibility", inspectRuleMenu(input))
                                            result.put("expansions", JsonInt(report.expansions))
                                            result.put("stoppedByDeadline", JsonBool(report.stoppedByDeadline))
                                            result.put("stoppedByLimit", JsonBool(report.stoppedByLimit))
                                            result.put("elapsedMillis", JsonInt(clock.monotonicMillis() - start))
                                            result.put("menuVersion", JsonInt(input.menu.menuVersion))
                                            result.put("menu", input.menu.toJson())
                                            jsonResponse(ctx, 200, result)
                                    }
                                }
                            } catch (_: Exception) {
                                jsonError(ctx, 400, "INVALID_INPUT",
                                    "参数无效；人数须为1–12，预算为整数分，请至少提交一人的需求")
                            }
                    }
                )
                router.pages(serveFrontend("web"))
        }
    )
    println(
        "Algorithm dev: ${publicOrigin} (listen ${host}:${port}) | ${initial.restaurant.name} | ${initial.dishes.size} dishes | read-only SQLite")
    server.serve()
    return 0
}
