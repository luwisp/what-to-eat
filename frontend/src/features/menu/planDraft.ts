import type { RecommendationItem } from "../../shared/contracts";
export interface PlanDraft {
  version: number;
  items: RecommendationItem[];
}
const key = (room: string, member: string) =>
  `juxiaobao:plan:${room}:${member}`;
export function readPlan(room: string, member: string): PlanDraft | null {
  try {
    const value = JSON.parse(localStorage.getItem(key(room, member)) ?? "null");
    if (
      !value ||
      !Number.isSafeInteger(value.version) ||
      !Array.isArray(value.items) ||
      value.items.length > 100
    )
      return null;
    if (
      value.items.some(
        (i: RecommendationItem) =>
          !["dish", "setMeal"].includes(i.itemType) ||
          typeof i.itemId !== "string" ||
          !Number.isInteger(i.quantity) ||
          i.quantity < 1 ||
          i.quantity > 100,
      )
    )
      return null;
    return value;
  } catch {
    return null;
  }
}
export function writePlan(room: string, member: string, draft: PlanDraft) {
  try {
    localStorage.setItem(key(room, member), JSON.stringify(draft));
  } catch {}
}
export function clearPlan(room: string, member: string) {
  try {
    localStorage.removeItem(key(room, member));
  } catch {}
}
export function changePlanItem(
  items: RecommendationItem[],
  item: RecommendationItem,
  quantity: number,
) {
  if (!Number.isInteger(quantity) || quantity < 0 || quantity > 100)
    return items;
  const matches = (i: RecommendationItem) =>
    i.itemId === item.itemId && i.itemType === item.itemType;
  if (!quantity) return items.filter((i) => !matches(i));
  return items.some(matches)
    ? items.map((i) => (matches(i) ? { ...i, quantity } : i))
    : [...items, { ...item, quantity }];
}
