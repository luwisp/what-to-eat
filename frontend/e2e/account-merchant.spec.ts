import { test, expect } from "@playwright/test";

// API contracts only for teammate-owned account/catalog endpoints. Room traffic
// in dining.spec.ts reaches the real Cangjie component integration server.
test("optional account defaults save only long-term fields and return locally", async ({
  page,
}) => {
  let loggedIn = false;
  let saved: Record<string, unknown> | undefined;
  await page.route("**/api/user/**", async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.endsWith("/login")) {
      loggedIn = true;
      await route.fulfill({
        json: { id: "u", kind: "user", login: "someone", nickname: null },
      });
      return;
    }
    if (path.endsWith("/me")) {
      await route.fulfill({
        status: loggedIn ? 200 : 401,
        json: loggedIn
          ? { id: "u", kind: "user", login: "someone", nickname: null }
          : { error: { code: "UNAUTHORIZED", message: "请登录" } },
      });
      return;
    }
    if (path.endsWith("/default-settings")) {
      if (route.request().method() === "PUT")
        saved = route.request().postDataJSON();
      await route.fulfill({
        json: {
          userId: "u",
          allergens: ["花生"],
          avoidFoods: [],
          dietMode: "none",
          maxSpiceLevel: null,
          tastePreferences: [],
          updatedAt: 0,
          ...saved,
        },
      });
      return;
    }
    await route.fulfill({ status: 204 });
  });
  await page.goto("/account?returnTo=%2Fr%2FTEST");
  await page.getByLabel("账号", { exact: true }).fill("someone");
  await page.getByLabel("密码", { exact: true }).fill("a-password");
  await page.getByRole("button", { name: "登录", exact: true }).click();
  await expect(page.getByRole("heading", { name: "someone" })).toBeVisible();
  await page.getByRole("button", { name: "保存为我的默认设置" }).click();
  await expect(page.getByRole("status")).toContainText("已保存");
  expect(saved).toBeDefined();
  expect(Object.keys(saved!).sort()).toEqual(
    [
      "appetite",
      "allergens",
      "avoidFoods",
      "dietMode",
      "maxSpiceLevel",
      "tastePreferences",
    ].sort(),
  );
  await page.getByRole("button", { name: "返回原页面", exact: false }).click();
  await expect(page).toHaveURL(/\/r\/TEST$/);
});

test("merchant fields preserve unknown and exact cents; server errors retain form", async ({
  page,
}) => {
  let loggedIn = false;
  let written: Record<string, unknown> | undefined;
  const restaurant = {
    id: "r",
    ownerId: "m",
    restaurantCode: "TEST",
    name: "测试餐馆",
    description: "",
  };
  const entry = {
    restaurantCode: "TEST",
    link: "http://127.0.0.1:4173/r/TEST",
  };
  await page.route("**/api/merchant/**", async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.endsWith("/login")) {
      loggedIn = true;
      await route.fulfill({
        json: { id: "m", kind: "merchant", login: "merchant", nickname: null },
      });
      return;
    }
    if (path.endsWith("/me")) {
      await route.fulfill({
        status: loggedIn ? 200 : 401,
        json: loggedIn
          ? { id: "m", kind: "merchant", login: "merchant", nickname: null }
          : { error: { code: "UNAUTHORIZED", message: "请登录" } },
      });
      return;
    }
    if (path.endsWith("/restaurant")) {
      await route.fulfill({ json: { restaurant, entry } });
      return;
    }
    if (path.endsWith("/dishes")) {
      written = route.request().postDataJSON();
      await route.fulfill({
        status: 409,
        json: {
          error: { code: "CONFLICT", message: "测试：写入失败，原数据保留" },
        },
      });
      return;
    }
    await route.fulfill({ status: 204 });
  });
  await page.goto("/admin/");
  await page.getByLabel("账号", { exact: true }).fill("merchant");
  await page.getByLabel("密码", { exact: true }).fill("a-password");
  await page.getByRole("button", { name: "登录", exact: true }).click();
  await page.getByRole("button", { name: "新增菜品" }).click();
  await page.getByLabel("名称", { exact: true }).fill("招牌小炒");
  await page.getByLabel("当前价格（元）").fill("19.90");
  await page.getByLabel("食材（含调料").fill("土豆、青椒");
  await page.getByLabel("仍有不明食材").check();
  await page.getByRole("button", { name: "保存菜品" }).click();
  await expect(page.getByRole("alert")).toContainText("写入失败");
  expect(written?.priceFen).toBe(1990);
  expect(written?.ingredients).toEqual(["土豆", "青椒", "unknown"]);
  await expect(page.getByLabel("名称", { exact: true })).toHaveValue(
    "招牌小炒",
  );
  await page.getByRole("button", { name: "取消编辑", exact: true }).click();
  await page.getByRole("button", { name: "餐馆入口", exact: true }).click();
  await expect(
    page.getByRole("link", { name: entry.link, exact: true }),
  ).toHaveAttribute("href", entry.link);
});
