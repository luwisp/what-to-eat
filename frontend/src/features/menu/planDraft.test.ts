import { it, expect, vi } from "vitest";
import { readPlan, writePlan, clearPlan, changePlanItem } from "./planDraft";
const store = new Map<string, string>();
vi.stubGlobal("localStorage", {
  getItem: (k: string) => store.get(k) ?? null,
  setItem: (k: string, v: string) => store.set(k, v),
  removeItem: (k: string) => store.delete(k),
});
const a = {
  itemType: "dish",
  itemId: "a",
  name: "菜",
  quantity: 1,
  unitPriceFen: 100,
};
const b = { ...a, itemId: "b" };
it("menu roundtrip keeps the version and member scope; cancel removes only this draft", () => {
  writePlan("ROOM", "me", { version: 4, items: [a] });
  expect(readPlan("ROOM", "other")).toBeNull();
  expect(readPlan("ROOM", "me")).toEqual({ version: 4, items: [a] });
  clearPlan("ROOM", "me");
  expect(readPlan("ROOM", "me")).toBeNull();
});
it("quantity changes preserve dish order and reject invalid amounts", () => {
  const items = [a, b];
  expect(changePlanItem(items, a, 2)).toEqual([{ ...a, quantity: 2 }, b]);
  expect(changePlanItem(items, a, 0)).toEqual([b]);
  expect(changePlanItem(items, a, 1.5)).toEqual(items);
  expect(changePlanItem(items, a, 101)).toEqual(items);
  expect(items[0].quantity).toBe(1);
});
