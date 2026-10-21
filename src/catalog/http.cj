package huaiwei.catalog

import huaiwei.model.*
import huaiwei.store.*
import huaiwei.auth.*
import huaiwei.platform.*
import huaiwei.room.*
import stdx.encoding.json.*

class CatalogCommit {
    public var id = "";
    public var version: Int64 = 0
}

func owner(db: DatabaseSnapshot, actor: Actor): Restaurant {
    demand(actor.merchantId.isSome(), "UNAUTHENTICATED", "请先登录商家账号", status: 401)
    for (r in db.restaurants) {
        if (Some(r.ownerId) == actor.merchantId) {
            return r
        }
    }
    throw RoomFault("NOT_FOUND", "请先创建餐馆", status: 404)
}

func menu(db: DatabaseSnapshot, r: Restaurant): MenuSnapshot {
    roomMenu(db, Session(restaurantId: r.id))
}

public func registerCatalogRoutes(router: HttpRouter, repository: Repository, auth: AuthService, origin: String,
    onCommitted: (String, Int64) -> Unit): Unit {
    router.on(
        "GET",
        "/api/restaurants/:code/menu",
        {
            ctx, params =>
                let db = repository.read()
                for (r in db.restaurants) {
                    if (r.restaurantCode == params["code"]) {
                        jsonResponse(ctx, 200, menu(db, r).toJson());
                        return
                    }
                }
                jsonError(ctx, 404, "NOT_FOUND", "餐馆不存在")
        }
    )
    router.on("GET", "/api/merchant/restaurant", {
        ctx, _ => try {
            let db = repository.read();
            let r = owner(db, auth.resolve(ctx.request.headers.getFirst("cookie") ?? ""))
            let obj = JsonObject();
            obj.put("restaurant", r.toJson())
            obj.put("entry",
                RestaurantEntry(restaurantCode: r.restaurantCode, link: origin + "/r/" + r.restaurantCode).toJson())
            jsonResponse(ctx, 200, obj)
        } catch (e: RoomFault) {
            jsonError(ctx, e.error.status, e.error.code, e.error.message)
        }
    })
    for ((method, path) in [("POST", "/api/merchant/restaurant"), ("PUT", "/api/merchant/restaurant"),
        ("POST", "/api/merchant/dishes"), ("PUT", "/api/merchant/dishes/:id"), ("DELETE", "/api/merchant/dishes/:id"),
        ("POST", "/api/merchant/set-meals"), ("PUT", "/api/merchant/set-meals/:id"),
        ("DELETE", "/api/merchant/set-meals/:id")]) {
        let verb = method;
        let route = path
        router.on(verb, route, {
            ctx, params => try {
                let requestOrigin = ctx.request.headers.getFirst("origin")
                demand(if (let Some(v) <- requestOrigin) {
                    v == origin
                } else {
                    ctx.request.headers.getFirst("sec-fetch-site") != Some("cross-site")
                }, "INVALID_ORIGIN", "请求来源无效", status: 403)
                let actor = auth.resolve(ctx.request.headers.getFirst("cookie") ?? "")
                demand(actor.merchantId.isSome(), "UNAUTHENTICATED", "请先登录商家账号", status: 401)
                let body = if (verb == "DELETE") {
                    JsonObject()
                } else {
                    readJsonBody(ctx)
                }
                let committed = CatalogCommit()
                let result = repository.transact({
                    db => try {
                        if (route == "/api/merchant/restaurant" && verb == "POST") {
                            demand(!db.restaurants.any({r => Some(r.ownerId) == actor.merchantId}), "RESTAURANT_EXISTS",
                                "一个商家只能创建一家餐馆", status: 409)
                            let name = body["name"].asString().getValue().trimAscii()
                            demand(!name.isEmpty() && name.size <= 512, "INVALID_INPUT", "请填写餐馆名称")
                            var code = ""
                            for (_ in 0..32) {
                                let candidate = "R" + newId()[0..8]
                                if (!db.restaurants.any({r => r.restaurantCode.toAsciiLower() == candidate.toAsciiLower()}) &&
                                    !db.sessions.any({r => r.roomCode.toAsciiLower() == candidate.toAsciiLower()})) {
                                    code = candidate
                                    break
                                }
                            }
                            demand(!code.isEmpty(), "CODE_EXHAUSTED", "暂时无法分配餐馆码，请重试", status: 503)
                            let r = Restaurant(id: newId(), ownerId: actor.merchantId.getOrThrow(),
                                restaurantCode: code, name: name,
                                description: body["description"].asString().getValue())
                            db.restaurants = db.restaurants.concat([r])
                            db.menuVersions = db.menuVersions.concat([MenuVersion(restaurantId: r.id, menuVersion: 1)])
                            committed.id = r.id
                            committed.version = 1
                            return Outcome.Ok(db)
                        }
                        let r = owner(db, actor);
                        committed.id = r.id
                        if (route == "/api/merchant/restaurant") {
                            let name = body["name"].asString().getValue().trimAscii()
                            demand(!name.isEmpty(), "INVALID_INPUT", "请填写餐馆名称")
                            r.name = name
                            r.description = body["description"].asString().getValue()
                        } else {
                            let id = if (verb == "POST") {
                                newId()
                            } else {
                                params["id"]
                            }
                            if (route.contains("/dishes")) {
                                if (verb != "POST") {
                                    demand(db.dishes.any({d => d.id == id && d.restaurantId == r.id}), "NOT_FOUND",
                                        "菜品不存在或无权修改", status: 404)
                                }
                                if (verb == "DELETE") {
                                    demand(!db.setMeals.any({m => m.components.any({c => c.dishId == id})}),
                                        "DISH_REFERENCED", "请先调整引用该菜的套餐", status: 409)
                                    db.dishes = db.dishes.filter({d => d.id != id})
                                    db.mealMetadata = db.mealMetadata.filter({m => m.dishId != id})
                                } else {
                                    let input = DishInput.fromJson(body);
                                    let valid = validateDishInput(input)
                                    if (let Err(e) <- valid) {
                                        return Outcome.Err(e)
                                    }
                                    let obj = input.toJson();
                                    obj.put("id", JsonString(id));
                                    obj.put("restaurantId", JsonString(r.id))
                                    let d = Dish.fromJson(obj);
                                    d.ingredients = normalizeIngredients(d.ingredients)
                                    db.dishes = db.dishes.filter({old => old.id != id}).concat([d])
                                    var role = if (d.category == "hot") {
                                        "hotMain"
                                    } else if (d.category == "cold") {
                                        "coldMain"
                                    } else {
                                        d.category
                                    }
                                    if (let Some(v) <- body.get("mealRole")) {
                                        role = v.asString().getValue()
                                    }
                                    demand(["hotMain", "coldMain", "side", "staple", "soup", "drink"].contains(role),
                                        "INVALID_INPUT", "用餐角色无效")
                                    let fact = DishMealFacts(dishId: id, role: role,
                                        stapleUnits: if (role == "staple" && body.containsKey("singleServing") &&
                                            body["singleServing"].asBool().getValue()) {
                                            Some(1)
                                        } else {
                                            None
                                        }, stapleKind: if (d.name == "米饭") {
                                            "rice"
                                        } else if (d.name.contains("面")) {
                                            "noodles"
                                        } else {
                                            "other"
                                        }, primaryIngredients: if (body.containsKey("primaryIngredients")) {
                                            body["primaryIngredients"]
                                                .asArray()
                                                .getItems()
                                                .toArray()
                                                .map({v => v.asString().getValue()})
                                                .filter({i => d.ingredients.contains(i) && i != "unknown"})
                                        } else {
                                            []
                                        },
                                        vegetable: body.containsKey("vegetable") && body["vegetable"]
                                            .asBool()
                                            .getValue())
                                    db.mealMetadata = db.mealMetadata.filter({m => m.dishId != id}).concat([fact])
                                }
                            } else {
                                if (verb != "POST") {
                                    demand(db.setMeals.any({m => m.id == id && m.restaurantId == r.id}), "NOT_FOUND",
                                        "套餐不存在或无权修改", status: 404)
                                }
                                if (verb == "DELETE") {
                                    db.setMeals = db.setMeals.filter({m => m.id != id})
                                } else {
                                    let input = SetMealInput.fromJson(body);
                                    let valid = validateSetMealInput(input)
                                    if (let Err(e) <- valid) {
                                        return Outcome.Err(e)
                                    }
                                    for (c in input.components) {
                                        demand(db.dishes.any({d => d.id == c.dishId && d.restaurantId == r.id}),
                                            "INVALID_COMPONENT", "套餐须引用同店菜品")
                                    }
                                    let obj = input.toJson();
                                    obj.put("id", JsonString(id));
                                    obj.put("restaurantId", JsonString(r.id))
                                    db.setMeals = db.setMeals.filter({m => m.id != id}).concat([SetMeal.fromJson(obj)])
                                }
                            }
                        }
                        for (v in db.menuVersions) {
                            if (v.restaurantId == r.id) {
                                v.menuVersion++;
                                committed.version = v.menuVersion
                            }
                        }
                        Outcome.Ok(db)
                    } catch (e: RoomFault) {
                        Outcome.Err(e.error)
                    } catch (_: Exception) {
                        Outcome.Err(DomainError("INVALID_INPUT", "字段格式无效"))
                    }
                })
                match (result) {
                    case Err(e) => jsonError(ctx, e.status, e.code, e.message)
                    case Ok(_) =>
                        onCommitted(committed.id, committed.version);
                        ctx.responseBuilder.status(204);
                        ()
                }
            } catch (e: RoomFault) {
                jsonError(ctx, e.error.status, e.error.code, e.error.message)
            } catch (_: Exception) {
                jsonError(ctx, 400, "INVALID_INPUT", "请求格式无效")
            }
        })
    }
}
