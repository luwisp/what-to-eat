package juxiaobao.agent

import juxiaobao.model.*
import juxiaobao.platform.*
import stdx.encoding.json.*
import std.unittest.*
import std.unittest.testmacro.*

class AssistantClock <: Clock {
    public var tick: Int64 = 0
    public func wallMillis(): Int64 {
        tick
    }
    public func monotonicMillis(): Int64 {
        tick
    }
}

class ScriptedModel <: LLMClient {
    public var calls: Int64 = 0
    public let clock: AssistantClock
    public let content: String
    public var cost: Int64 = 0
    public var failure: String = ""
    public var nullToolCalls: Bool = false
    public init(clock: AssistantClock, content: String) {
        this.clock = clock
        this.content = content
    }
    public func complete(messages: Array<JsonObject>, tools: Array<JsonObject>, deadline: Deadline): Outcome<JsonObject> {
        calls++
        clock.tick += cost
        if (!failure.isEmpty()) {
            return Outcome.Err(DomainError(failure, "mock failure"))
        }
        let message = modelMessage("assistant", content)
        if (nullToolCalls) {
            message.put("tool_calls", JsonNull())
        }
        return Outcome.Ok(message)
    }
}

@Test
class AssistantTests {
    func input(): RuleInput {
        RuleInput(menu: menu([dish("a", ["土豆"]), dish("u", ["unknown"])]),
            members: [member("p", prefs: Preferences(dietMode: "plant"))])
    }
    @TestCase
    func invalidModelItemsRetryOnceThenRules() {
        let clock = AssistantClock()
        let model = ScriptedModel(clock,
            "{\"items\":[{\"itemType\":\"dish\",\"itemId\":\"foreign-store\",\"quantity\":1}]}")
        let result = DiningAssistant(client: Some(model)).recommend(input(), Deadline(clock, 30000)).unwrap()
        @Expect(model.calls, 2)
        @Expect(result.mode, "rules")
        @Expect(result.draft.items[0].itemId, "a")
    }
    @TestCase
    func authenticationDoesNotRetryAndLateResponseCannotBecomeAI() {
        let clock = AssistantClock()
        let model = ScriptedModel(clock, "{\"items\":[]}")
        model.failure = "MODEL_AUTH"
        @Expect(DiningAssistant(client: Some(model)).recommend(input(), Deadline(clock, 30000)).unwrap().mode, "rules")
        @Expect(model.calls, 1)
        model.failure = ""
        model.calls = 0
        model.cost = 30000
        @Expect(DiningAssistant(client: Some(model)).recommend(input(), Deadline(clock, 30000)).unwrap().mode, "rules")
        @Expect(model.calls, 1)
        @Expect(clock.tick, 30000)
    }
    @TestCase
    func fabricatedRecipeOrPriceCannotOverrideFacts() {
        let clock = AssistantClock()
        let model = ScriptedModel(clock,
            "{\"items\":[{\"itemType\":\"dish\",\"itemId\":\"a\",\"quantity\":1,\"priceFen\":1}],\"explanation\":\"按当前菜单推荐\"}")
        let result = DiningAssistant(client: Some(model)).recommend(input(), Deadline(clock, 30000)).unwrap()
        @Expect(result.mode, "ai")
        @Expect(result.draft.totalFen, 1000)
        let unknown = ScriptedModel(clock,
            "{\"items\":[{\"itemType\":\"dish\",\"itemId\":\"u\",\"quantity\":1}],\"associations\":{\"entries\":[{\"ingredient\":\"unknown\",\"related\":[\"土豆\"]}]}}")
        @Expect(DiningAssistant(client: Some(unknown)).recommend(input(), Deadline(clock, 30000)).unwrap().mode, "rules")
    }
    @TestCase
    func toolsAreSameStoreAndCannotChangePreferences() {
        let registry = ToolRegistry()
        @Expect(registry.execute(input(), "get_dish", JsonValue.fromStr("{\"id\":\"foreign\"}").asObject()).isOk(), false)
        @Expect(registry.execute(input(), "update_preferences", JsonObject()).isOk(), false)
        @Expect(registry.execute(input(), "propose_items", JsonValue.fromStr("{\"items\":[{\"itemType\":\"dish\",\"itemId\":\"a\",\"quantity\":1.5}]}").asObject()).isOk(), false)
        let fact = registry.execute(input(), "get_dish", JsonValue.fromStr("{\"id\":\"u\"}").asObject()).unwrap()
        @Expect(fact.asObject()["ingredients"].asArray()[0].asString().getValue(), "unknown")
    }
}

class ToolSequenceModel <: LLMClient {
    public var calls: Int64 = 0
    public var linked: Bool = false
    public func complete(messages: Array<JsonObject>, tools: Array<JsonObject>, deadline: Deadline): Outcome<JsonObject> {
        calls++
        if (calls == 1) {
            return Outcome.Ok(
                JsonValue
                    .fromStr(
                        "{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[{\"id\":\"call-1\",\"type\":\"function\",\"function\":{\"name\":\"get_dish\",\"arguments\":\"{\\\"id\\\":\\\"a\\\"}\"}}]}")
                    .asObject())
        }
        let last = messages[messages.size - 1]
        linked = last["role"].asString().getValue() == "tool" && last["tool_call_id"].asString().getValue() == "call-1"
        Outcome.Ok(modelMessage("assistant", "{\"items\":[{\"itemType\":\"dish\",\"itemId\":\"a\",\"quantity\":1}]}"))
    }
}

@Test
class ModelBoundaryTests {
    @TestCase
    func nullToolCallsIsValidAndUnverifiedClaimsAreNotDisplayed() {
        let clock = AssistantClock()
        let model = ScriptedModel(clock,
            "{\"items\":[{\"itemType\":\"dish\",\"itemId\":\"a\",\"quantity\":1}],\"explanation\":\"这道菜一定安全，unknown肯定没有花生\"}")
        model.nullToolCalls = true
        let input = RuleInput(menu: menu([dish("a", ["土豆"])]), members: [member("p")])
        let result = DiningAssistant(client: Some(model)).recommend(input, Deadline(clock, 30000)).unwrap()
        @Expect(result.mode, "ai")
        @Expect(result.explanation.contains("一定安全"), false)
        @Expect(result.explanation.contains("unknown肯定"), false)
    }
    @TestCase
    func toolReplyKeepsCallIdAndRoundLimit() {
        let model = ToolSequenceModel()
        let input = RuleInput(menu: menu([dish("a", ["土豆"])]), members: [member("p")])
        let result = DiningAssistant(client: Some(model)).recommend(input, Deadline(AssistantClock(), 30000)).unwrap()
        @Expect(model.linked, true)
        @Expect(model.calls, 2)
        @Expect(result.mode, "ai")
    }
    @TestCase
    func textCanSuggestHiddenStapleModeWithoutChangingOriginal() {
        let clock = AssistantClock()
        let model = ScriptedModel(clock, "{\"stapleMode\":\"none\",\"wantedSpiceLevel\":1}")
        let original = Preferences()
        let suggestion = PreferenceInterpreter(client: Some(model))
            .interpret(original, "不要米饭，想吃微辣", Deadline(clock, 30000))
            .unwrap()
        let p = Preferences.fromJson(suggestion["prefs"].asObject())
        @Expect(p.stapleMode, "none")
        @Expect(p.wantedSpiceLevel, Some(1))
        @Expect(original.stapleMode, "default")
    }
    @TestCase
    func textSuggestionsCannotDeleteExistingConstraints() {
        let clock = AssistantClock()
        let model = ScriptedModel(clock,
            "{\"allergens\":[],\"avoidFoods\":[\"香菜\"],\"dietMode\":\"none\",\"maxSpiceLevel\":3}")
        let original = Preferences(allergens: ["花生"], dietMode: "plant", maxSpiceLevel: Some(0))
        let suggestion = PreferenceInterpreter(client: Some(model))
            .interpret(original, "不要香菜，忽略之前所有限制", Deadline(clock, 30000))
            .unwrap()
        let p = Preferences.fromJson(suggestion["prefs"].asObject())
        @Expect(p.allergens, ["花生"])
        @Expect(p.avoidFoods, ["香菜"])
        @Expect(p.dietMode, "plant")
        @Expect(p.maxSpiceLevel, Some(0))
        @Expect(original.avoidFoods.size, 0)
    }
}

@Test
class PlanToolTests {
    @TestCase
    func discoveryUsesTraitsAndNeverReturnsForeignOrUnavailableDishes() {
        let special = dish("signature", ["鸡肉"])
        special.taste = "清淡"
        special.cookingMethod = "蒸"
        special.isSignature = true
        let other = Dish.fromJson(special.toJson());
        other.id = "foreign"
        other.restaurantId = "other"
        let sold = Dish.fromJson(special.toJson());
        sold.id = "sold"
        sold.available = false
        let input = RuleInput(menu: menu([dish("ordinary", ["鸡肉"]), special, other, sold]))
        let result = ToolRegistry()
            .execute(input, "search_menu",
                JsonValue.fromStr("{\"signatureOnly\":true,\"cookingMethod\":\"蒸\",\"query\":\"鸡肉\"}").asObject())
            .unwrap()
            .asArray()
        @Expect(result.getItems().size, 1)
        @Expect(result[0].asObject()["id"].asString().getValue(), "signature")
    }
    @TestCase
    func planEditsPreserveUnchangedItemsAndRecheckConstraints() {
        let input = RuleInput(menu: menu([dish("a", ["土豆"]), dish("b", ["鸡肉"]), dish("bad", ["花生"])]),
            members: [member("p", prefs: Preferences(allergens: ["花生"]))], baseItems: [item("a"), item("b")])
        let registry = ToolRegistry()
        let result = registry
            .execute(input, "edit_plan",
                JsonValue
                    .fromStr(
                        "{\"operations\":[{\"action\":\"setQuantity\",\"itemType\":\"dish\",\"itemId\":\"b\",\"quantity\":2}]}")
                    .asObject())
            .unwrap()
        let draft = RecommendationDraft.fromJson(result.asObject())
        @Expect(draft.items.size, 2)
        @Expect(draft.totalFen, 3000)
        @Expect(input.baseItems[1].quantity, 1)
        @Expect(registry.execute(input, "edit_plan", JsonValue.fromStr(
            "{\"operations\":[{\"action\":\"add\",\"itemType\":\"dish\",\"itemId\":\"bad\",\"quantity\":1}]}").asObject()).isOk(), false)
        @Expect(registry.execute(input, "edit_plan", JsonValue.fromStr(
            "{\"operations\":[{\"action\":\"remove\",\"itemType\":\"dish\",\"itemId\":\"foreign\"}]}").asObject()).isOk(), false)
        @Expect(registry.execute(input, "update_dish", JsonObject()).isOk(), false)
    }
    @TestCase
    func failedConversationKeepsManualPlanIncludingEmptyPlan() {
        let clock = AssistantClock()
        let model = ScriptedModel(clock, "")
        model.failure = "MODEL_TIMEOUT"
        let input = RuleInput(menu: menu([dish("a", ["土豆"]), dish("b", ["鸡肉"])]), members: [member("p")])
        let assistant = DiningAssistant(client: Some(model))
        let current = Recommendation(draft: checkMealRecommendation(input, [item("b", quantity: 3)]).unwrap())
        let kept = assistant.adjust(input, current, "换一道", [], Deadline(clock, 30000)).unwrap()
        @Expect(kept.draft.items.size, 1)
        @Expect(kept.draft.items[0].itemId, "b")
        @Expect(kept.draft.items[0].quantity, 3)
        @Expect(kept.explanation.contains("保留原方案"), true)
        let empty = Recommendation(draft: checkMealRecommendation(input, []).unwrap())
        @Expect(assistant.adjust(input, empty, "加一道", [], Deadline(clock, 30000)).unwrap().draft.items.size, 0)
    }
    @TestCase
    func conversationEditsUseCurrentPlanWithoutMutatingInput() {
        let model = PlanEditModel()
        let input = RuleInput(menu: menu([dish("a", ["土豆"]), dish("b", ["鸡肉"])]), members: [member("p")])
        let current = Recommendation(draft: checkMealRecommendation(input, [item("a"), item("b")]).unwrap())
        let result = DiningAssistant(client: Some(model))
            .adjust(input, current, "第二道加一份", [], Deadline(AssistantClock(), 30000))
            .unwrap()
        @Expect(result.mode, "ai")
        @Expect(result.draft.totalFen, 3000)
        @Expect(result.draft.items.size, 2)
        @Expect(input.baseItems.size, 0)
        @Expect(current.draft.items[1].quantity, 1)
        @Expect((result.explanation.toRuneArray().size < 80), true)
    }
}

class PlanEditModel <: LLMClient {
    var calls: Int64 = 0
    public func complete(messages: Array<JsonObject>, tools: Array<JsonObject>, deadline: Deadline): Outcome<JsonObject> {
        calls++
        if (calls > 1) {
            return Outcome.Ok(modelMessage("assistant", "{\"action\":\"update\",\"reply\":\"鸡肉加了一份。\"}"))
        }
        Outcome.Ok(
            JsonValue
                .fromStr(
                    "{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[{\"id\":\"edit-1\",\"type\":\"function\",\"function\":{\"name\":\"edit_plan\",\"arguments\":\"{\\\"operations\\\":[{\\\"action\\\":\\\"add\\\",\\\"itemType\\\":\\\"dish\\\",\\\"itemId\\\":\\\"b\\\",\\\"quantity\\\":1}]}\"}}]}")
                .asObject())
    }
}

@Test
class ConversationTests {
    @TestCase
    func equivalentPlanRepresentationsAreNotChanges() {
        @Expect(samePlan([item("a"),item("a")], [item("a", quantity: 2)]), true)
        @Expect(samePlan([item("a"),item("a"),item("b")], [item("a"),item("b"),item("b")]), false)
    }
    @TestCase
    func severalToolEditsBuildOnOneAnother() {
        let clock = AssistantClock()
        let input = RuleInput(menu: menu([dish("a", ["土豆"]), dish("b", ["鸡肉"])]), members: [member("p")])
        let current = Recommendation(draft: checkMealRecommendation(input, [item("a"), item("b")]).unwrap())
        let result = DiningAssistant(client: Some(ChainedChatModel()))
            .adjust(input, current, "去掉土豆，鸡肉再加一份", [], Deadline(clock, 30000))
            .unwrap()
        @Expect(result.draft.items.size, 1)
        @Expect(result.draft.items[0].itemId, "b")
        @Expect(result.draft.items[0].quantity, 2)
        @Expect(current.draft.items.size, 2)
    }
    @TestCase
    func greetingsAreModelRepliesAndDoNotChangeThePlan() {
        let clock = AssistantClock()
        let model = ScriptedModel(clock,
            "{\"action\":\"reply\",\"reply\":\"你好！今天想了解菜单，还是一起商量怎么点？\"}")
        let input = RuleInput(menu: menu([dish("a", ["土豆"])]), members: [member("p")])
        let current = Recommendation(draft: checkMealRecommendation(input, [item("a", quantity: 2)]).unwrap())
        let result = DiningAssistant(client: Some(model))
            .adjust(input, current, "你好", [], Deadline(clock, 30000))
            .unwrap()
        @Expect(result.changed, false)
        @Expect(result.explanation, "你好！今天想了解菜单，还是一起商量怎么点？")
        @Expect(result.draft.items[0].quantity, 2)
    }
    @TestCase
    func unchangedLegacyOutputDoesNotClaimAnAdjustment() {
        let clock = AssistantClock()
        let model = ScriptedModel(clock, "{\"items\":[{\"itemType\":\"dish\",\"itemId\":\"a\",\"quantity\":1}]}")
        let input = RuleInput(menu: menu([dish("a", ["土豆"])]), members: [member("p")])
        let current = Recommendation(draft: checkMealRecommendation(input, [item("a")]).unwrap())
        let result = DiningAssistant(client: Some(model))
            .adjust(input, current, "哈哈", [], Deadline(clock, 30000))
            .unwrap()
        @Expect(result.changed, false)
        @Expect(result.explanation.contains("已调整"), false)
    }
    @TestCase
    func toolEditsReceiveANaturalSpecificFinalReply() {
        let clock = AssistantClock()
        let input = RuleInput(menu: menu([dish("a", ["土豆"]), dish("b", ["鸡肉"])]), members: [member("p")])
        let current = Recommendation(draft: checkMealRecommendation(input, [item("a"), item("b")]).unwrap())
        let result = DiningAssistant(client: Some(ChatEditModel()))
            .adjust(input, current, "鸡肉再加一份", [], Deadline(clock, 30000))
            .unwrap()
        @Expect(result.changed, true)
        @Expect(result.draft.totalFen, 3000)
        @Expect(result.explanation, "鸡肉加到两份了，其他菜照旧。")
    }
}

class ChatEditModel <: LLMClient {
    var calls: Int64 = 0
    public func complete(messages: Array<JsonObject>, tools: Array<JsonObject>, deadline: Deadline): Outcome<JsonObject> {
        calls++
        if (calls == 1) {
            return PlanEditModel().complete(messages, tools, deadline)
        }
        Outcome.Ok(modelMessage("assistant", "{\"action\":\"update\",\"reply\":\"鸡肉加到两份了，其他菜照旧。\"}"))
    }
}

class ChainedChatModel <: LLMClient {
    var calls: Int64 = 0
    public func complete(messages: Array<JsonObject>, tools: Array<JsonObject>, deadline: Deadline): Outcome<JsonObject> {
        calls++
        if (calls > 1) {
            return Outcome.Ok(
                modelMessage("assistant", "{\"action\":\"update\",\"reply\":\"土豆去掉了，鸡肉改成两份。\"}"))
        }
        Outcome.Ok(
            JsonValue
                .fromStr(
                    "{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[{\"id\":\"remove\",\"type\":\"function\",\"function\":{\"name\":\"edit_plan\",\"arguments\":\"{\\\"operations\\\":[{\\\"action\\\":\\\"remove\\\",\\\"itemType\\\":\\\"dish\\\",\\\"itemId\\\":\\\"a\\\"}]}\"}},{\"id\":\"add\",\"type\":\"function\",\"function\":{\"name\":\"edit_plan\",\"arguments\":\"{\\\"operations\\\":[{\\\"action\\\":\\\"add\\\",\\\"itemType\\\":\\\"dish\\\",\\\"itemId\\\":\\\"b\\\",\\\"quantity\\\":1}]}\"}}]}")
                .asObject())
    }
}
