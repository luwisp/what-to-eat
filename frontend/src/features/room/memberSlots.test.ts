import { expect, it } from "vitest";
import {
  memberPlaceholders,
  nextCompanionName,
  mealMemberName,
} from "./memberSlots";

it("fills a four-person table with three unfilled companion slots", () => {
  const members = [{ nickname: "发起人" }];
  expect(memberPlaceholders(4, members)).toEqual([
    { nickname: "同行人 A" },
    { nickname: "同行人 B" },
    { nickname: "同行人 C" },
  ]);
  expect(members).toEqual([{ nickname: "发起人" }]);
  expect(memberPlaceholders(1, members)).toEqual([]);
});

it("reduces slots after joining or filling and follows changed table sizes", () => {
  const members = [{ nickname: "发起人" }, { nickname: "同行人 B" }];
  expect(memberPlaceholders(4, members)).toEqual([
    { nickname: "同行人 A" },
    { nickname: "同行人 C" },
  ]);
  members.push({ nickname: "扫码加入者" });
  expect(memberPlaceholders(4, members)).toEqual([{ nickname: "同行人 A" }]);
  expect(memberPlaceholders(3, members)).toEqual([]);
  expect(memberPlaceholders(2, members)).toEqual([]);
  expect(memberPlaceholders(5, members)).toHaveLength(2);
});

it("does not reuse existing companion names with or without spaces", () => {
  expect(
    nextCompanionName([{ nickname: "同行人A" }, { nickname: "同行人 B" }]),
  ).toBe("同行人 C");
});

it("keeps unique alphabetical names for tables larger than 26 companions", () => {
  const slots = memberPlaceholders(100, [{ nickname: "发起人" }]);
  expect(slots).toHaveLength(99);
  expect(slots[25]?.nickname).toBe("同行人 Z");
  expect(slots[26]?.nickname).toBe("同行人 AA");
  expect(new Set(slots.map((slot) => slot.nickname)).size).toBe(99);
});

it("names pending meal allocations consistently with the remaining seats", () => {
  const members = [
    { id: "host", nickname: "发起人" },
    { id: "companion", nickname: "同行人 B" },
    { id: "guest", nickname: "小明" },
  ];
  const placeholders = memberPlaceholders(5, members);
  expect(mealMemberName("pending:0", members, placeholders)).toBe("同行人 A");
  expect(mealMemberName("pending:1", members, placeholders)).toBe("同行人 C");
  expect(mealMemberName("guest", members, placeholders)).toBe("小明");
  expect(mealMemberName("pending:99", members, placeholders)).toBe("同行人");
});
