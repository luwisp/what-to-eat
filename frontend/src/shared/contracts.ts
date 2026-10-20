// Generated from scripts/generate-models.py; edit the shared schema.
export interface Actor {
  userId: string | null;
  merchantId: string | null;
  visitorId: string | null;
}
export interface PasswordDigest {
  algorithm: string;
  iterations: number;
  saltHex: string;
  hashHex: string;
}
export interface AccountView {
  id: string;
  kind: string;
  login: string;
  nickname: string | null;
}
export interface UserAccount {
  id: string;
  login: string;
  passwordHash: PasswordDigest;
  nickname: string | null;
  createdAt: number;
}
export interface MerchantAccount {
  id: string;
  login: string;
  passwordHash: PasswordDigest;
  restaurantId: string | null;
  createdAt: number;
}
export interface StoredAuthSession {
  tokenHash: string;
  kind: string;
  accountId: string;
  expiresAt: number;
}
export interface StoredVisitorSession {
  tokenHash: string;
  visitorId: string;
  expiresAt: number;
}
export interface AuthSession {
  account: AccountView;
  setCookie: string;
}
export interface VisitorSession {
  actor: Actor;
  setCookie: string | null;
}
export interface ExtraWish {
  dishId: string;
  quantity: number;
}
export interface DishMealFacts {
  dishId: string;
  role: string;
  vegetable: boolean;
  primaryIngredients: string[];
  stapleUnits: number | null;
  stapleKind: string;
  soupGroupId: string;
  servesMax: number | null;
}
export interface MealAllocation {
  memberId: string;
  coverage: number;
  halfDishNeed: number;
  halfDishAllocated: number;
  stapleDishId: string | null;
  stapleOptOut: boolean;
}
export interface Preferences {
  appetite: string;
  stapleMode: string;
  stapleDishId: string | null;
  wantedIngredients: string[];
  wantedExtras: ExtraWish[];
  wantedSpiceLevel: number | null;
  allergens: string[];
  avoidFoods: string[];
  dietMode: string;
  maxSpiceLevel: number | null;
  tastePreferences: string[];
  wantedDishIds: string[];
  wantedSetMealIds: string[];
  note: string;
}
export interface UserDefaultSettings {
  appetite: string;
  userId: string;
  allergens: string[];
  avoidFoods: string[];
  dietMode: string;
  maxSpiceLevel: number | null;
  tastePreferences: string[];
  updatedAt: number;
}
export interface Restaurant {
  id: string;
  ownerId: string;
  restaurantCode: string;
  name: string;
  description: string;
}
export interface RestaurantEntry {
  restaurantCode: string;
  link: string;
}
export interface DishInput {
  name: string;
  description: string;
  taste: string;
  cookingMethod: string;
  priceFen: number;
  imageUrl: string;
  category: string;
  ingredients: string[];
  spiceLevel: number;
  available: boolean;
  isSignature: boolean;
}
export interface Dish {
  id: string;
  restaurantId: string;
  name: string;
  description: string;
  taste: string;
  cookingMethod: string;
  priceFen: number;
  imageUrl: string;
  category: string;
  ingredients: string[];
  spiceLevel: number;
  available: boolean;
  isSignature: boolean;
}
export interface SetMealComponent {
  dishId: string;
  quantity: number;
}
export interface SetMealInput {
  name: string;
  imageUrl: string;
  components: SetMealComponent[];
  priceFen: number;
}
export interface SetMeal {
  id: string;
  restaurantId: string;
  name: string;
  imageUrl: string;
  components: SetMealComponent[];
  priceFen: number;
}
export interface MenuVersion {
  restaurantId: string;
  menuVersion: number;
}
export interface MenuSnapshot {
  mealMetadata: DishMealFacts[];
  restaurant: Restaurant;
  menuVersion: number;
  dishes: Dish[];
  setMeals: SetMeal[];
}
export interface Session {
  id: string;
  roomCode: string;
  restaurantId: string;
  hostParticipantId: string;
  state: string;
  people: number;
  budgetPerPersonFen: number | null;
  stateVersion: number;
  menuVersion: number;
  createdAt: number;
  expiresAt: number;
  recommendationInvalid: boolean;
}
export interface Participant {
  id: string;
  sessionId: string;
  userId: string | null;
  visitorId: string | null;
  nickname: string;
  avatarColor: string | null;
  submitted: boolean;
  preferences: Preferences;
  draft: Preferences;
  joinedAt: number;
  source: string;
  filledByParticipantId: string | null;
}
export interface ParticipantView {
  id: string;
  nickname: string;
  avatarColor: string | null;
  submitted: boolean;
  preferences: Preferences | null;
  source: string;
  filledByParticipantId: string | null;
}
export interface RecommendationItem {
  itemType: string;
  itemId: string;
  quantity: number;
  name: string;
  unitPriceFen: number;
}
export interface ExpandedDish {
  dish: Dish;
  quantity: number;
}
export interface ExpandedMenu {
  dishes: ExpandedDish[];
  totalFen: number;
}
export interface MemberFit {
  status: string;
  reasons: string[];
}
export interface DishFit {
  dishId: string;
  memberId: string;
  status: string;
  reasons: string[];
}
export interface UnmetWish {
  memberId: string;
  itemType: string;
  itemId: string;
  reason: string;
}
export interface RecommendationDraft {
  mealStatus: string;
  estimatedHotNeed: number;
  estimatedHotSupply: number;
  mealMembers: MealAllocation[];
  items: RecommendationItem[];
  expandedDishes: ExpandedDish[];
  fits: DishFit[];
  totalFen: number;
  undercoveredIds: string[];
  uncoveredIds: string[];
  unmetWishes: UnmetWish[];
  budgetWarning: string | null;
  notices: string[];
  associations: IngredientAssociations;
}
export interface Recommendation {
  id: string;
  sessionId: string;
  roomVersion: number;
  menuVersion: number;
  mode: string;
  draft: RecommendationDraft;
  canConfirm: boolean;
  createdAt: number;
  accepted: boolean;
}
export interface ChatMessage {
  id: string;
  sessionId: string;
  sender: string;
  role: string;
  content: string;
  createdAt: number;
}
export interface DedupeRecord {
  scope: string;
  actorId: string;
  requestId: string;
  operation: string;
  resultJson: string;
  expiresAt: number;
}
export interface RecommendationJob {
  id: string;
  sessionId: string;
  requesterId: string;
  requestId: string;
  roomVersion: number;
  menuVersion: number;
  startedAt: number;
  status: string;
  adjustment: string | null;
  text: string | null;
}
export interface IngredientAssociation {
  ingredient: string;
  related: string[];
}
export interface IngredientAssociations {
  entries: IngredientAssociation[];
}
export interface RuleInput {
  menu: MenuSnapshot;
  members: Participant[];
  people: number;
  budgetPerPersonFen: number | null;
  associations: IngredientAssociations;
  baseItems: RecommendationItem[];
  adjustment: string | null;
}
export interface CreateSessionInput {
  restaurantCode: string;
  people: number;
  budgetPerPersonFen: number | null;
}
export interface RoomSnapshot {
  session: Session;
  restaurantCode: string;
  stateVersion: number;
  menuVersion: number;
  members: ParticipantView[];
  self: Participant | null;
  recommendation: Recommendation | null;
  recommendationInvalid: boolean;
  job: RecommendationJob | null;
  messages: ChatMessage[];
}
export interface StoreConfig {
  path: string;
}
export interface DatabaseSnapshot {
  mealMetadata: DishMealFacts[];
  schemaVersion: number;
  users: UserAccount[];
  merchants: MerchantAccount[];
  authSessions: StoredAuthSession[];
  visitorSessions: StoredVisitorSession[];
  defaultSettings: UserDefaultSettings[];
  restaurants: Restaurant[];
  menuVersions: MenuVersion[];
  dishes: Dish[];
  setMeals: SetMeal[];
  sessions: Session[];
  participants: Participant[];
  recommendations: Recommendation[];
  chatMessages: ChatMessage[];
  dedupeRecords: DedupeRecord[];
  jobs: RecommendationJob[];
}
