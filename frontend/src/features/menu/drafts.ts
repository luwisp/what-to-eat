import type { Preferences, UserDefaultSettings } from "../../shared/contracts";
export type DraftKey = `restaurant:${string}` | `room:${string}:${string}`;
export const emptyPreferences = (): Preferences => ({
  allergens: [],
  avoidFoods: [],
  dietMode: "none",
  maxSpiceLevel: null,
  tastePreferences: [],
  wantedDishIds: [],
  wantedSetMealIds: [],
  note: "",
});
type DraftStorage = Pick<Storage, "getItem" | "setItem">;
function clean(value: unknown): Preferences {
  const p = emptyPreferences();
  if (!value || typeof value !== "object") return p;
  const v = value as Record<string, unknown>;
  for (const key of [
    "allergens",
    "avoidFoods",
    "tastePreferences",
    "wantedDishIds",
    "wantedSetMealIds",
  ] as const)
    if (Array.isArray(v[key]))
      p[key] = (v[key] as unknown[])
        .filter((x): x is string => typeof x === "string")
        .slice(0, 100);
  if (["none", "ovoLacto", "plant"].includes(String(v.dietMode)))
    p.dietMode = String(v.dietMode);
  if (
    Number.isInteger(v.maxSpiceLevel) &&
    Number(v.maxSpiceLevel) >= 0 &&
    Number(v.maxSpiceLevel) <= 3
  )
    p.maxSpiceLevel = Number(v.maxSpiceLevel);
  if (typeof v.note === "string")
    p.note = Array.from(v.note).slice(0, 200).join("");
  return p;
}
export function loadDraft(
  key: DraftKey,
  storage: DraftStorage = localStorage,
): Preferences {
  try {
    return clean(JSON.parse(storage.getItem("huaiwei:draft:" + key) ?? "null"));
  } catch {
    return emptyPreferences();
  }
}
export function hasDraft(key: DraftKey): boolean {
  try {
    return localStorage.getItem("huaiwei:draft:" + key) !== null;
  } catch {
    return false;
  }
}
export function saveDraft(
  key: DraftKey,
  prefs: Preferences,
  storage: DraftStorage = localStorage,
) {
  try {
    storage.setItem("huaiwei:draft:" + key, JSON.stringify(clean(prefs)));
  } catch {
    /* In-memory input remains usable if storage is unavailable. */
  }
}
export function applyDefaults(
  defaults: Partial<UserDefaultSettings>,
  existing: Preferences | null,
): Preferences {
  if (existing) return clean(existing);
  const result = clean(defaults);
  result.note = "";
  result.wantedDishIds = [];
  result.wantedSetMealIds = [];
  return result;
}
