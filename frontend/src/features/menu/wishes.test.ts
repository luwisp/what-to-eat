import { expect, it } from "vitest";
import { emptyPreferences, loadDraft, saveDraft } from "./drafts";
import { changeDishWish, dishWishQuantity } from "./wishes";
it("preserves other dishes, persists quantities and removes a wish completely at zero", () => {
  let prefs = emptyPreferences();
  prefs.wantedDishIds = ["legacy"];
  expect(dishWishQuantity(prefs, "legacy")).toBe(1);
  prefs = changeDishWish(prefs, "hot", 3);
  prefs = changeDishWish(prefs, "rice", 2);
  expect(dishWishQuantity(prefs, "hot")).toBe(3);
  expect(prefs.wantedDishIds).toEqual(["legacy", "hot", "rice"]);
  const data = new Map<string, string>();
  const storage = {
    getItem: (key: string) => data.get(key) ?? null,
    setItem: (key: string, value: string) => {
      data.set(key, value);
    },
  };
  saveDraft("restaurant:PORTIONS", prefs, storage);
  expect(
    dishWishQuantity(loadDraft("restaurant:PORTIONS", storage), "hot"),
  ).toBe(3);
  prefs = changeDishWish(prefs, "hot", 0);
  expect(dishWishQuantity(prefs, "hot")).toBe(0);
  expect(prefs.wantedExtras.some((wish) => wish.dishId === "hot")).toBe(false);
  expect(dishWishQuantity(prefs, "rice")).toBe(2);
  expect(changeDishWish(prefs, "rice", 101)).toBe(prefs);
});
