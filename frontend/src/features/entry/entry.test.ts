import { describe, it, expect } from "vitest";
import { resolveEntry, safeReturnTo } from "./entry";
describe("entry boundaries", () => {
  it("separates restaurant and room links and rejects outside links", () => {
    expect(
      resolveEntry("https://dining.test/r/TEST", "https://dining.test"),
    ).toEqual({ kind: "restaurant", code: "TEST" });
    expect(resolveEntry("/s/A3F9", "https://dining.test")).toEqual({
      kind: "room",
      code: "A3F9",
    });
    expect(
      resolveEntry("https://other.test/r/TEST", "https://dining.test"),
    ).toBeNull();
    expect(
      resolveEntry("javascript:alert(1)", "https://dining.test"),
    ).toBeNull();
    expect(resolveEntry("TEST", "https://dining.test")).toEqual({
      kind: "restaurant",
      code: "TEST",
    });
  });
  it("allows only internal return paths", () => {
    for (const v of [
      "//evil.test",
      "/\\evil.test",
      "https://evil.test",
      "javascript:alert(1)",
    ])
      expect(safeReturnTo(v)).toBe("/");
    expect(safeReturnTo("/s/A3F9/preferences")).toBe("/s/A3F9/preferences");
  });
});
