import { test, expect } from "@playwright/test";

test("real accounts, defaults, two members, v3 meals, manual edits and confirmation", async ({
  browser,
}) => {
  const host = await browser.newContext(),
    guest = await browser.newContext();
  const h = await host.newPage(),
    g = await guest.newPage();
  const failures: string[] = [];
  h.on("pageerror", (e) => failures.push(e.message));
  await h.goto("/account");
  await h.getByRole("button", { name: "还没有账号，去注册" }).click();
  await h.getByLabel("账号", { exact: true }).fill("full-" + Date.now());
  await h.getByLabel("密码", { exact: true }).fill("test-password-123");
  await h.getByRole("button", { name: "注册账号", exact: true }).click();
  await expect(h.getByRole("status")).toContainText("注册成功");
  await h.getByLabel("密码", { exact: true }).fill("test-password-123");
  await h.getByRole("button", { name: "登录", exact: true }).click();
  await expect(
    h.getByRole("button", { name: "保存为我的默认设置" }),
  ).toBeVisible();
  await h.getByLabel("食量", { exact: true }).selectOption("large");
  await h.getByRole("button", { name: "保存为我的默认设置" }).click();
  await expect(h.getByRole("status")).toContainText("已保存");
  await h.goto("/r/LAOXIANGJI");
  await expect(
    h.getByRole("heading", { name: "老乡鸡", exact: true }),
  ).toBeVisible();
  await h.getByLabel("用餐人数").fill("2");
  await h.getByRole("button", { name: "创建聚餐局" }).click();
  await expect(h.getByRole("heading", { name: /聚餐局/ })).toBeVisible();
  const room = h.url();
  await h.getByRole("link", { name: "我的要求", exact: true }).click();
  await expect(h.getByLabel("食量", { exact: true })).toHaveValue("large");
  await h.getByRole("button", { name: "提交本局要求" }).click();
  await g.goto(room);
  await g.getByRole("link", { name: "我的要求", exact: true }).click();
  await g.getByRole("button", { name: "提交本局要求" }).click();
  await expect(
    h.getByText("2 人已填写 / 声明 2 人", { exact: false }),
  ).toBeVisible();
  await h.getByRole("button", { name: "看看怎么点", exact: true }).click();
  await expect(
    h.getByText("已满足当前估算用餐需求", { exact: false }),
  ).toBeVisible();
  await expect(h.getByText("热菜 3 / 3 份", { exact: false })).toBeVisible();
  await expect(h.getByRole("button", { name: "确认这桌方案" })).toBeEnabled();
  await h.getByRole("button", { name: "修改这桌方案" }).click();
  await h.getByRole("button", { name: "移除 米饭", exact: true }).click();
  await h.getByRole("button", { name: "保存并重新校验" }).click();
  await expect(
    h.getByText("当前方案仍有用餐缺口", { exact: false }),
  ).toBeVisible();
  await expect(h.getByRole("button", { name: "确认这桌方案" })).toHaveCount(0);
  const menu = await (
    await h.request.get("/api/restaurants/LAOXIANGJI/menu")
  ).json();
  const rice = menu.dishes.find((d: any) => d.name === "米饭");
  await h.getByRole("button", { name: "修改这桌方案" }).click();
  await h.getByLabel("添加菜品或套餐").selectOption(rice.id);
  await h.getByRole("button", { name: "加入方案", exact: true }).click();
  await h
    .locator(".result-editor > .row")
    .filter({ has: h.getByText("米饭", { exact: true }) })
    .getByLabel("份数")
    .fill("2");
  await h.getByRole("button", { name: "保存并重新校验" }).click();
  await expect(h.getByRole("button", { name: "确认这桌方案" })).toBeVisible();
  await h.getByRole("button", { name: "确认这桌方案" }).click();
  await expect(h.getByText("本桌已确认", { exact: false })).toBeVisible();
  await g.reload();
  await expect(g.getByText("本桌已确认", { exact: false })).toBeVisible();
  expect(failures).toEqual([]);
  await host.close();
  await guest.close();
});

test("real merchant menu writes, package references and live recommendation invalidation", async ({
  page,
}) => {
  await page.goto("/admin/");
  await page.getByRole("button", { name: "注册商家账号", exact: true }).click();
  await page.getByLabel("账号", { exact: true }).fill("merchant-" + Date.now());
  await page.getByLabel("密码", { exact: true }).fill("merchant-password-123");
  await page.getByRole("button", { name: "注册", exact: true }).click();
  await expect(page.getByRole("status")).toContainText("注册成功");
  await page.getByLabel("密码", { exact: true }).fill("merchant-password-123");
  await page.getByRole("button", { name: "登录", exact: true }).click();
  await page.getByLabel("餐馆名称", { exact: true }).fill("真实联调餐馆");
  await page.getByRole("button", { name: "保存餐馆资料" }).click();
  await expect(
    page.getByRole("heading", { name: "真实联调餐馆", exact: true }),
  ).toBeVisible();
  await page.getByRole("button", { name: "新增菜品" }).click();
  await page.getByLabel("名称", { exact: true }).fill("清蒸鸡肉");
  await page.getByLabel("当前价格（元）").fill("12.5");
  await page.getByLabel("食材（含调料", { exact: false }).fill("鸡肉、土豆");
  await page.getByLabel("主料（可选", { exact: false }).fill("鸡肉");
  await page.getByRole("button", { name: "保存菜品", exact: true }).click();
  await expect(page.getByRole("status")).toContainText("已保存");
  const own = await (await page.request.get("/api/merchant/restaurant")).json();
  const code = own.restaurant.restaurantCode;
  const rice = {
    name: "米饭",
    description: "一人份",
    taste: "清淡",
    cookingMethod: "蒸",
    priceFen: 200,
    imageUrl: "",
    category: "staple",
    ingredients: ["大米"],
    spiceLevel: 0,
    available: true,
    isSignature: false,
    mealRole: "staple",
    singleServing: true,
  };
  expect(
    (await page.request.post("/api/merchant/dishes", { data: rice })).status(),
  ).toBe(204);
  const menu = await (
    await page.request.get(`/api/restaurants/${code}/menu`)
  ).json();
  const chicken = menu.dishes.find((d: any) => d.name === "清蒸鸡肉");
  expect(
    menu.mealMetadata.find((f: any) => f.dishId === chicken.id)
      .primaryIngredients,
  ).toEqual(["鸡肉"]);
  expect(
    (
      await page.request.post("/api/merchant/set-meals", {
        data: {
          name: "鸡肉套餐",
          imageUrl: "",
          priceFen: 1400,
          components: [{ dishId: chicken.id, quantity: 1 }],
        },
      })
    ).status(),
  ).toBe(204);
  expect(
    (await page.request.delete(`/api/merchant/dishes/${chicken.id}`)).status(),
  ).toBe(409);
  await page.goto(`/r/${code}`);
  await page.getByLabel("用餐人数").fill("1");
  await page.getByRole("button", { name: "创建聚餐局" }).click();
  await page.getByRole("link", { name: "我的要求", exact: true }).click();
  await page.getByRole("button", { name: "提交本局要求" }).click();
  await page.getByRole("button", { name: "看看怎么点", exact: true }).click();
  await expect(
    page.getByText("已满足当前估算用餐需求", { exact: false }),
  ).toBeVisible();
  expect(
    (
      await page.request.put(`/api/merchant/dishes/${chicken.id}`, {
        data: {
          ...chicken,
          priceFen: 1500,
          mealRole: "hotMain",
          primaryIngredients: ["鸡肉"],
        },
      })
    ).status(),
  ).toBe(204);
  await expect(
    page.getByText("需求或菜单已变化", { exact: false }),
  ).toBeVisible();
  await expect(page.getByRole("button", { name: "确认这桌方案" })).toHaveCount(
    0,
  );
});

test("simple preferences keep menu wishes, allergies and implicit staple choice", async ({
  page,
}) => {
  await page.setViewportSize({ width: 393, height: 852 });
  await page.goto("/r/LAOXIANGJI");
  await page.getByLabel("用餐人数").fill("1");
  await page.getByRole("button", { name: "创建聚餐局" }).click();
  await page.getByRole("link", { name: "我的要求", exact: true }).click();
  await expect(page.getByLabel("本局昵称", { exact: true })).toHaveCount(0);
  await expect(page.getByLabel("本次主食")).toHaveCount(0);
  await page.getByRole("button", { name: "香菜", exact: true }).click();
  const allergy = page.locator(".allergy-picker");
  await allergy.locator("summary").click();
  await allergy.getByRole("button", { name: "花生", exact: true }).click();
  await allergy.locator("summary").click();
  await expect(
    page.getByRole("button", { name: "馄饨", exact: true }),
  ).toBeVisible();
  await expect(page.getByLabel("搜索本店食材")).not.toBeVisible();
  await page.locator(".ingredient-picker > summary").click();
  await expect(page.getByLabel("搜索本店食材")).toBeVisible();
  await page.getByLabel("还有想说的？", { exact: false }).fill("想吃清淡一点");
  await page.getByRole("link", { name: "看菜单，选想吃的菜 →" }).click();
  const menu = await (
    await page.request.get("/api/restaurants/LAOXIANGJI/menu")
  ).json();
  const wonton = menu.dishes.find(
    (d: any) =>
      d.available && (d.name.includes("馄饨") || d.name.includes("混沌")),
  );
  await page.getByRole("button", { name: "主食", exact: true }).click();
  await page
    .getByRole("article")
    .filter({
      has: page.getByRole("heading", { name: wonton.name, exact: true }),
    })
    .getByRole("button", { name: /想吃这道/ })
    .click();
  const drink = menu.dishes.find(
    (d: any) => d.available && d.category === "drink",
  );
  await page.getByRole("button", { name: "饮品", exact: true }).click();
  await page
    .getByRole("article")
    .filter({
      has: page.getByRole("heading", { name: drink.name, exact: true }),
    })
    .getByRole("button", { name: /想吃这道/ })
    .click();
  await page.getByRole("button", { name: "完成选择" }).click();
  await expect(
    page.getByRole("button", { name: "移除想吃" + drink.name }),
  ).toBeVisible();
  await page.getByRole("button", { name: "只存草稿" }).click();
  await page.reload();
  await expect(page.getByLabel("还有想说的？", { exact: false })).toHaveValue(
    "想吃清淡一点",
  );
  await expect(
    page.getByRole("button", { name: "香菜", exact: true }),
  ).toHaveAttribute("aria-pressed", "true");
  await expect(allergy.locator("summary")).toContainText("花生");
  await expect(
    page.getByRole("button", { name: "移除想吃" + wonton.name }),
  ).toHaveAttribute("aria-pressed", "true");
  await page.screenshot({
    path: "/tmp/huaiwei-preferences-simple.png",
    fullPage: true,
  });
  await page.setViewportSize({ width: 320, height: 700 });
  const submit = page.getByRole("button", { name: "提交本局要求" });
  await expect(submit).toBeInViewport();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBeTruthy();
  await submit.click();
  await page.getByRole("button", { name: "看看怎么点", exact: true }).click();
  await expect(
    page.getByText("已满足当前估算用餐需求", { exact: false }),
  ).toBeVisible();
  const state = await (
    await page.request.get("/api/sessions/" + page.url().split("/s/")[1])
  ).json();
  expect(
    state.recommendation.draft.items.some(
      (i: any) => i.name.includes("馄饨") || i.name.includes("混沌"),
    ),
  ).toBeTruthy();
  expect(
    state.recommendation.draft.items.some((i: any) => i.name === "米饭"),
  ).toBeFalsy();
});

test("account error recovery, relogin defaults and local return navigation", async ({
  page,
}) => {
  const login = "account-audit-" + Date.now();
  await page.goto("/account?returnTo=/r/LAOXIANGJI");
  await page.getByRole("button", { name: "还没有账号，去注册" }).click();
  await page.getByLabel("账号", { exact: true }).fill(login);
  await page.getByLabel("密码", { exact: true }).fill("short");
  await page.getByRole("button", { name: "注册账号", exact: true }).click();
  await expect(page.getByRole("alert")).toBeVisible();
  await page.getByLabel("密码", { exact: true }).fill("audit-password-123");
  await page.getByRole("button", { name: "注册账号", exact: true }).click();
  await expect(page.getByRole("alert")).toHaveCount(0);
  await expect(page.getByRole("status")).toContainText("注册成功");
  await page.getByLabel("密码", { exact: true }).fill("wrong-password");
  await page.getByRole("button", { name: "登录", exact: true }).click();
  await expect(page.getByRole("alert")).toContainText("账号或密码错误");
  await expect(page.getByRole("status")).toHaveCount(0);
  await page.getByLabel("密码", { exact: true }).fill("audit-password-123");
  await page.getByRole("button", { name: "登录", exact: true }).click();
  await expect(page.getByRole("alert")).toHaveCount(0);
  await expect(page.getByRole("status")).toHaveCount(0);
  await page.getByLabel("食量", { exact: true }).selectOption("large");
  await page.getByRole("button", { name: "香菜", exact: true }).click();
  await page.getByRole("button", { name: "保存为我的默认设置" }).click();
  await expect(page.getByRole("status")).toContainText("已保存");
  await page.getByRole("button", { name: "退出账号" }).click();
  await expect(
    page.getByRole("button", { name: "登录", exact: true }),
  ).toBeVisible();
  await page.getByLabel("密码", { exact: true }).fill("audit-password-123");
  await page.getByRole("button", { name: "登录", exact: true }).click();
  await expect(page.getByLabel("食量", { exact: true })).toHaveValue("large");
  await expect(
    page.getByRole("button", { name: "香菜", exact: true }),
  ).toHaveAttribute("aria-pressed", "true");
  await page.reload();
  await expect(page.getByLabel("食量", { exact: true })).toHaveValue("large");
  await page.getByRole("button", { name: "← 返回原页面" }).click();
  await expect(page).toHaveURL(/\/r\/LAOXIANGJI$/);
});
