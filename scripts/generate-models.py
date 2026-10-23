#!/usr/bin/env python3
"""Generate the shared Cangjie records and strict JSON codecs from one schema.

Business validation stays in src/model/validation.cj. This script does not infer
ingredients, authorize actors or silently migrate stored schemas.
"""
from pathlib import Path

SCHEMA = {
    'Actor': 'userId:?String merchantId:?String visitorId:?String',
    'PasswordDigest': 'algorithm:String iterations:Int64 saltHex:String hashHex:String',
    'AccountView': 'id:String kind:String login:String nickname:?String',
    'UserAccount': 'id:String login:String passwordHash:PasswordDigest nickname:?String createdAt:Int64',
    'MerchantAccount': 'id:String login:String passwordHash:PasswordDigest restaurantId:?String createdAt:Int64',
    'StoredAuthSession': 'tokenHash:String kind:String accountId:String expiresAt:Int64',
    'StoredVisitorSession': 'tokenHash:String visitorId:String expiresAt:Int64',
    'AuthSession': 'account:AccountView setCookie:String',
    'VisitorSession': 'actor:Actor setCookie:?String',
    'ExtraWish': 'dishId:String quantity:Int64=1',
    'DishMealFacts': 'dishId:String role:String=unknown vegetable:Bool primaryIngredients:[String] stapleUnits:?Int64 stapleKind:String=other soupGroupId:String servesMax:?Int64',
    'MealDishPortion': 'dishId:String halfDishUnits:Int64',
    'MealAllocation': 'memberId:String coverage:Int64 halfDishNeed:Int64 halfDishAllocated:Int64 stapleDishId:?String stapleOptOut:Bool provisional:Bool hotDishes:[MealDishPortion]',
    'Preferences': 'appetite:String=normal stapleMode:String=default stapleDishId:?String wantedIngredients:[String] wantedExtras:[ExtraWish] wantedSpiceLevel:?Int64 allergens:[String] avoidFoods:[String] dietMode:String=none maxSpiceLevel:?Int64 tastePreferences:[String] wantedDishIds:[String] wantedSetMealIds:[String] note:String',
    'UserDefaultSettings': 'appetite:String=normal userId:String allergens:[String] avoidFoods:[String] dietMode:String=none maxSpiceLevel:?Int64 tastePreferences:[String] updatedAt:Int64',
    'Restaurant': 'id:String ownerId:String restaurantCode:String name:String description:String',
    'RestaurantEntry': 'restaurantCode:String link:String',
    'DishInput': 'name:String description:String taste:String cookingMethod:String priceFen:Int64 imageUrl:String category:String=hot ingredients:[String] spiceLevel:Int64 available:Bool=true isSignature:Bool',
    'Dish': 'id:String restaurantId:String name:String description:String taste:String cookingMethod:String priceFen:Int64 imageUrl:String category:String=hot ingredients:[String] spiceLevel:Int64 available:Bool=true isSignature:Bool',
    'SetMealComponent': 'dishId:String quantity:Int64=1',
    'SetMealInput': 'name:String imageUrl:String components:[SetMealComponent] priceFen:Int64',
    'SetMeal': 'id:String restaurantId:String name:String imageUrl:String components:[SetMealComponent] priceFen:Int64',
    'MenuVersion': 'restaurantId:String menuVersion:Int64',
    'MenuSnapshot': 'mealMetadata:[DishMealFacts] restaurant:Restaurant menuVersion:Int64 dishes:[Dish] setMeals:[SetMeal]',
    'Session': 'id:String roomCode:String restaurantId:String hostParticipantId:String state:String=open people:Int64=4 budgetPerPersonFen:?Int64 stateVersion:Int64=1 menuVersion:Int64 createdAt:Int64 expiresAt:Int64 recommendationInvalid:Bool',
    'Participant': 'id:String sessionId:String userId:?String visitorId:?String nickname:String avatarColor:?String submitted:Bool preferences:Preferences draft:Preferences joinedAt:Int64 source:String=self filledByParticipantId:?String',
    'ParticipantView': 'id:String nickname:String avatarColor:?String submitted:Bool preferences:?Preferences source:String=self filledByParticipantId:?String',
    'RecommendationItem': 'itemType:String=dish itemId:String quantity:Int64=1 name:String unitPriceFen:Int64',
    'ExpandedDish': 'dish:Dish quantity:Int64=1',
    'ExpandedMenu': 'dishes:[ExpandedDish] totalFen:Int64',
    'MemberFit': 'status:String=fit reasons:[String]',
    'DishFit': 'dishId:String memberId:String status:String=fit reasons:[String]',
    'UnmetWish': 'memberId:String itemType:String itemId:String reason:String',
    'RecommendationDraft': 'mealStatus:String=legacy estimatedHotNeed:Int64 estimatedHotSupply:Int64 mealMembers:[MealAllocation] items:[RecommendationItem] expandedDishes:[ExpandedDish] fits:[DishFit] totalFen:Int64 undercoveredIds:[String] uncoveredIds:[String] unmetWishes:[UnmetWish] budgetWarning:?String notices:[String] associations:IngredientAssociations',
    'Recommendation': 'id:String sessionId:String roomVersion:Int64 menuVersion:Int64 mode:String=rules draft:RecommendationDraft canConfirm:Bool createdAt:Int64 accepted:Bool',
    'ChatMessage': 'id:String sessionId:String sender:String role:String content:String createdAt:Int64',
    'DedupeRecord': 'scope:String actorId:String requestId:String operation:String resultJson:String expiresAt:Int64',
    'RecommendationJob': 'id:String sessionId:String requesterId:String requestId:String roomVersion:Int64 menuVersion:Int64 startedAt:Int64 status:String=inProgress adjustment:?String text:?String',
    'IngredientAssociation': 'ingredient:String related:[String]',
    'IngredientAssociations': 'entries:[IngredientAssociation]',
    'RuleInput': 'menu:MenuSnapshot members:[Participant] people:Int64=4 budgetPerPersonFen:?Int64 associations:IngredientAssociations baseItems:[RecommendationItem] adjustment:?String',
    'CreateSessionInput': 'restaurantCode:String people:Int64=4 budgetPerPersonFen:?Int64',
    'RoomSnapshot': 'session:Session restaurantCode:String stateVersion:Int64 menuVersion:Int64 members:[ParticipantView] self:?Participant recommendation:?Recommendation recommendationInvalid:Bool job:?RecommendationJob messages:[ChatMessage]',
    'StoreConfig': 'path:String',
    'DatabaseSnapshot': 'mealMetadata:[DishMealFacts] schemaVersion:Int64=1 users:[UserAccount] merchants:[MerchantAccount] authSessions:[StoredAuthSession] visitorSessions:[StoredVisitorSession] defaultSettings:[UserDefaultSettings] restaurants:[Restaurant] menuVersions:[MenuVersion] dishes:[Dish] setMeals:[SetMeal] sessions:[Session] participants:[Participant] recommendations:[Recommendation] chatMessages:[ChatMessage] dedupeRecords:[DedupeRecord] jobs:[RecommendationJob]',
}


def cj_type(kind):
    if kind.startswith('['):
        return f'Array<{cj_type(kind[1:-1])}>'
    return kind


def default(kind, explicit=None):
    if explicit is not None:
        return f'"{explicit}"' if kind == 'String' else explicit
    if kind.startswith('?'):
        return 'None'
    if kind.startswith('['):
        return '[]'
    return {'String': '""', 'Int64': '0', 'Bool': 'false'}.get(kind, f'{kind}()')


def encode(kind, value):
    if kind.startswith('?'):
        return f'match ({value}) {{ case Some(v) => {encode(kind[1:], "v")}; case None => JsonNull() }}'
    if kind.startswith('['):
        return f'JsonArray({value}.map({{item => {encode(kind[1:-1], "item")} }}))'
    scalar = {'String': 'JsonString', 'Int64': 'JsonInt', 'Bool': 'JsonBool'}.get(kind)
    return f'{scalar}({value})' if scalar else f'{value}.toJson()'


def decode(kind, value):
    if kind.startswith('?'):
        return f'match ({value}) {{ case _: JsonNull => None; case _ => Some({decode(kind[1:], value)}) }}'
    if kind.startswith('['):
        return f'{value}.asArray().getItems().toArray().map({{item => {decode(kind[1:-1], "item")} }})'
    scalar = {'String': 'asString', 'Int64': 'asInt', 'Bool': 'asBool'}.get(kind)
    return f'{value}.{scalar}().getValue()' if scalar else f'{kind}.fromJson({value}.asObject())'


MIGRATED = {
 'MealAllocation': {'provisional','hotDishes'},
 'Preferences': {'appetite','stapleMode','stapleDishId','wantedIngredients','wantedExtras','wantedSpiceLevel'},
 'UserDefaultSettings': {'appetite'}, 'MenuSnapshot': {'mealMetadata'},
 'DatabaseSnapshot': {'mealMetadata'},
 'RecommendationDraft': {'mealStatus','estimatedHotNeed','estimatedHotSupply','mealMembers'},
}
def field_decode(record, key, kind, fallback):
    value = decode(kind, f'obj["{key}"]')
    if key in MIGRATED.get(record, set()):
        return f'if (obj.containsKey("{key}")) {{ {value} }} else {{ {fallback} }}'
    return value

def generate():
    lines = ['// Generated by scripts/generate-models.py; edit its schema and regenerate.',
             'package juxiaobao.model', '', 'import stdx.encoding.json.*', '']
    for name, spec in SCHEMA.items():
        fields = []
        for field in spec.split():
            key, rest = field.split(':', 1)
            kind, _, explicit = rest.partition('=')
            fields.append((key, kind, default(kind, explicit or None)))
        lines.append(f'public class {name} {{')
        lines.extend(f'    public var {key}: {cj_type(kind)}' for key, kind, _ in fields)
        args = ',\n        '.join(f'{key}!: {cj_type(kind)} = {d}' for key, kind, d in fields)
        lines.append(f'\n    public init({args}) {{')
        lines.extend(f'        this.{key} = {key}' for key, _, _ in fields)
        lines.extend(['    }', ''])
        if name in {'Actor', 'AuthSession', 'VisitorSession', 'StoreConfig'}:
            lines.extend(['}', ''])
            continue
        lines.extend(['    public func toJson(): JsonObject {', '        let obj = JsonObject()'])
        lines.extend(f'        obj.put("{key}", {encode(kind, key)})' for key, kind, _ in fields)
        lines.extend(['        return obj', '    }', '', f'    public static func fromJson(obj: JsonObject): {name} {{'])
        if name == 'DatabaseSnapshot':
            lines.append('        if (obj["schemaVersion"].asInt().getValue() != 1) { throw Exception("Unsupported database schema") }')
        args = ',\n            '.join(f'{key}: {field_decode(name, key, kind, d)}' for key, kind, d in fields)
        lines.extend([f'        return {name}({args})', '    }', '}', ''])
    Path('src/model/entities.cj').write_text('\n'.join(lines))
    def ts_type(kind):
        if kind.startswith('['):
            return ts_type(kind[1:-1]) + '[]'
        if kind.startswith('?'):
            return ts_type(kind[1:]) + ' | null'
        return {'String': 'string', 'Int64': 'number', 'Bool': 'boolean'}.get(kind, kind)
    types = ['// Generated from scripts/generate-models.py; edit the shared schema.']
    for name, spec in SCHEMA.items():
        types.append(f'export interface {name} {{')
        for field in spec.split():
            key, kind = field.split(':', 1)
            types.append(f'  {key}: {ts_type(kind.split("=")[0])};')
        types.append('}')
    dest = Path('frontend/src/shared/contracts.ts')
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text('\n'.join(types) + '\n')


if __name__ == '__main__':
    generate()
