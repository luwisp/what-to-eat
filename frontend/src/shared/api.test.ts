import { it, expect } from "vitest";
import { priceFen, copyJson } from "./api";
import { reactive } from "vue";
it("parses yuan exactly and rejects imprecise or unsafe values", () => {
  expect(priceFen("19.90")).toBe(1990);
  expect(priceFen("0.01")).toBe(1);
  for (const v of ["-1", "1.001", "1e2", "NaN", "9007199254740991"])
    expect(() => priceFen(v)).toThrow();
});
it("copies JSON DTOs from Vue proxies without losing arrays or mutating input", () => {
  const p = reactive({ note: "草稿", ids: ["a"] });
  const c = copyJson(p);
  c.ids.push("b");
  expect(p.ids).toEqual(["a"]);
  expect(c.note).toBe("草稿");
});
