import { it, expect } from "vitest";
import {
  emptyPreferences,
  loadDraft,
  saveDraft,
  applyDefaults,
} from "./drafts";
const data = new Map<string, string>();
const storage = {
  getItem: (key: string) => data.get(key) ?? null,
  setItem: (key: string, v: string) => {
    data.set(key, v);
  },
};
it("keeps drafts scoped per restaurant and room member", () => {
  const p = emptyPreferences();
  p.wantedDishIds = ["dish"];
  p.note = "还要汤";
  saveDraft("restaurant:A", p, storage);
  expect(loadDraft("restaurant:B", storage).wantedDishIds).toEqual([]);
  expect(loadDraft("restaurant:A", storage).note).toBe("还要汤");
  expect(loadDraft("room:A3F9:someone-else", storage).note).toBe("");
});
it("defaults cannot import today wishes or replace an existing draft", () => {
  const p = emptyPreferences();
  p.note = "本局";
  const defaults = {
    ...emptyPreferences(),
    allergens: ["花生"],
    wantedDishIds: ["foreign"],
    note: "不能带入",
  };
  expect(applyDefaults(defaults, p)).toEqual(p);
  const result = applyDefaults(defaults, null);
  expect(result.allergens).toEqual(["花生"]);
  expect(result.wantedDishIds).toEqual([]);
  expect(result.note).toBe("");
});
it("corrupt local data falls back without inventing submitted requirements", () => {
  storage.setItem("huaiwei:draft:restaurant:BAD", "{broken");
  expect(loadDraft("restaurant:BAD", storage)).toEqual(emptyPreferences());
});
