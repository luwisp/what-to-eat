import { test, expect } from "@playwright/test";

test("unfilled seats show provisional dish portions and become personal after filling", async ({
  page,
}) => {
  await page.goto("/r/LAOXIANGJI");
  await page.getByLabel("用餐人数").fill("4");
  await page.getByRole("button", { name: "创建聚餐局" }).click();
  await expect(page).toHaveURL(/\/s\/[A-Za-z0-9]+$/);
  await expect(
    page.getByRole("button", { name: "＋ 帮同行人填写", exact: true }),
  ).toHaveCount(0);
  await expect(page.locator(".member-placeholder")).toHaveCount(3);
  await page.getByRole("link", { name: "填写我的要求", exact: true }).click();
  await page.getByRole("button", { name: "确认并返回" }).click();
  await page.getByRole("button", { name: "确认方案", exact: true }).click();
  await expect(page).toHaveURL(/\/result$/);
  await page.getByText("看看每个人怎么吃", { exact: true }).click();
  const cards = page.locator(".member-meal-card");
  const provisional = page.locator(".member-meal-card.is-provisional");
  await expect(cards).toHaveCount(4);
  await expect(provisional).toHaveCount(3);
  for (const name of ["同行人 A", "同行人 B", "同行人 C"]) {
    const card = provisional.filter({ hasText: name });
    await expect(card).toContainText("按正常饭量预分配，饮食要求待确认");
    await expect(card).toContainText("热菜 1 / 1 份");
    await expect(card.locator(".member-staple")).toContainText("米饭");
    await expect(card.locator(".member-fit-dishes > span")).not.toHaveCount(0);
    await expect(card.locator(".member-fit-dishes")).toContainText("份");
  }
  await expect(page.getByRole("button", { name: "确认这桌方案" })).toHaveCount(
    0,
  );
  await page.reload();
  await page.getByText("看看每个人怎么吃", { exact: true }).click();
  await expect(provisional).toHaveCount(3);
  await page.getByRole("link", { name: "← 返回这一桌" }).click();
  await page.getByRole("button", { name: "填写同行人 B的要求" }).click();
  const companion = page.getByRole("dialog", { name: "帮同行人填写" });
  await companion.getByRole("button", { name: "保存同行人要求" }).click();
  await expect(companion).not.toBeVisible();
  await expect(page.locator(".member-placeholder")).toHaveCount(2);
  await expect(page.locator(".dining-members li")).toHaveCount(4);
  await page
    .getByRole("button", { name: "修改同行人 B的要求", exact: true })
    .click();
  const editor = page.getByRole("dialog", { name: "编辑同行人的要求" });
  await expect(editor.getByLabel("称呼")).toHaveValue("同行人 B");
  await editor.getByRole("button", { name: "取消", exact: true }).click();
  await page
    .getByRole("button", { name: "重新搭配这一桌", exact: true })
    .click();
  await expect(page).toHaveURL(/\/result$/);
  await page.getByText("看看每个人怎么吃", { exact: true }).click();
  await expect(cards).toHaveCount(4);
  await expect(provisional).toHaveCount(2);
  await expect(cards.filter({ hasText: "同行人 B" })).not.toHaveClass(
    /is-provisional/,
  );
});

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
  await h.getByLabel("用户名", { exact: true }).fill("小宝");
  await h.getByRole("button", { name: "保存用户名" }).click();
  await expect(h.getByRole("status")).toContainText("用户名已保存");
  await h.reload();
  await expect(h.getByLabel("用户名", { exact: true })).toHaveValue("小宝");
  await h.screenshot({ path: "/tmp/juxiaobao-account.png", fullPage: true });
  await h.getByLabel("食量", { exact: true }).focus();
  await h.keyboard.press("End");
  await h.keyboard.press("ArrowLeft");
  await h.getByRole("button", { name: "保存为我的默认设置" }).click();
  await expect(h.getByRole("status")).toContainText("已保存");
  await h.goto("/r/LAOXIANGJI");
  await expect(
    h.getByRole("heading", { name: "老乡鸡", exact: true }),
  ).toBeVisible();
  await h.getByLabel("用餐人数").fill("2");
  await h.getByRole("button", { name: "创建聚餐局" }).click();
  await expect(h).toHaveURL(/\/s\/[A-Za-z0-9]+$/);
  const room = h.url();
  await h.getByRole("link", { name: /^(填写|编辑)我的要求$/ }).click();
  await expect(h.getByLabel("食量", { exact: true })).toHaveValue("2");
  await h.getByRole("button", { name: "确认并返回" }).click();
  await g.goto(room);
  await g.getByRole("link", { name: /^(填写|编辑)我的要求$/ }).click();
  await g.getByRole("button", { name: "确认并返回" }).click();
  await expect(h.getByText("2 / 2 人已填写", { exact: false })).toBeVisible();
  await h.getByRole("button", { name: "确认方案", exact: true }).click();
  await expect(h.getByText("饭菜已配齐", { exact: false })).toBeVisible();
  await h.getByText("看看每个人怎么吃", { exact: true }).click();
  await expect(h.getByText("热菜 3 / 3 份", { exact: false })).toBeVisible();
  await expect(h.getByRole("button", { name: "确认这桌方案" })).toBeEnabled();
  await h.getByRole("button", { name: "修改这桌方案" }).click();
  await h.getByRole("button", { name: "增加米饭", exact: true }).click();
  await expect(h.getByLabel("米饭份数", { exact: true })).toHaveValue("3");
  await h.getByRole("button", { name: "取消修改", exact: true }).click();
  await h.reload();
  await expect(h.getByLabel("米饭份数", { exact: true })).toHaveCount(0);
  await h.getByRole("button", { name: "修改这桌方案" }).click();
  await expect(h.getByLabel("米饭份数", { exact: true })).toHaveValue("2");

  await h.getByRole("button", { name: "移除 米饭", exact: true }).click();
  await h.getByRole("button", { name: "保存并重新校验" }).click();
  await expect(
    h.getByText("还有需要补齐的地方", { exact: false }),
  ).toBeVisible();
  await expect(h.getByRole("button", { name: "确认这桌方案" })).toHaveCount(0);
  await h.getByRole("button", { name: "修改这桌方案" }).click();
  await h.getByRole("link", { name: "＋ 从菜单加菜" }).click();
  await h.getByRole("button", { name: "主食", exact: true }).click();
  await h.getByRole("button", { name: "增加米饭", exact: true }).click();
  await h.getByRole("button", { name: "增加米饭", exact: true }).click();
  await h.getByRole("button", { name: "返回方案", exact: true }).click();
  await expect(h.getByLabel("米饭份数", { exact: true })).toHaveValue("2");
  await expect(h.locator(".result-editor")).toHaveCount(0);
  await h.screenshot({ path: "/tmp/juxiaobao-plan-edit.png", fullPage: true });
  await h.getByRole("button", { name: "保存并重新校验" }).click();
  await expect(h.getByRole("button", { name: "确认这桌方案" })).toBeVisible();
  await h.getByText("看看每个人怎么吃", { exact: true }).click();
  await h.screenshot({ path: "/tmp/juxiaobao-result.png", fullPage: true });
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
  await expect(page.getByLabel("用餐角色", { exact: true })).toHaveCount(0);
  await expect(page.getByLabel("图片链接", { exact: true })).toHaveCount(0);
  const exampleMenu = await (
    await page.request.get("/api/restaurants/LAOXIANGJI/menu")
  ).json();
  const imageUrl = exampleMenu.dishes.find((d: any) => d.imageUrl).imageUrl;
  const image = await (await page.request.get(imageUrl)).body();
  await page
    .getByLabel("上传菜品图片", { exact: true })
    .setInputFiles({ name: "菜品.jpg", mimeType: "image/jpeg", buffer: image });
  await expect(page.getByAltText("菜品图片预览")).toHaveAttribute(
    "src",
    /^\/uploads\/menu\//,
  );

  await page.getByLabel("当前价格（元）").fill("12.5");
  await page.getByLabel("食材（含调料", { exact: false }).fill("鸡肉、土豆");
  await page.getByLabel("主料（可选", { exact: false }).fill("鸡肉");
  await page.getByRole("button", { name: "保存菜品", exact: true }).click();
  await expect(page.getByRole("status")).toContainText("已保存");
  await page.getByLabel("搜索菜品", { exact: true }).fill("不存在的菜");
  await expect(page.getByText("没有匹配的菜，换个词试试")).toBeVisible();
  await page.getByLabel("搜索菜品", { exact: true }).fill("鸡肉");
  await page
    .getByRole("button", { name: "编辑 清蒸鸡肉", exact: true })
    .click();
  await expect(page.getByRole("dialog")).toBeVisible();
  await expect(page.getByLabel("主料（可选", { exact: false })).toHaveValue(
    "鸡肉",
  );
  await page.getByRole("button", { name: "取消编辑" }).click();
  await page.screenshot({
    path: "/tmp/juxiaobao-merchant.png",
    fullPage: true,
  });
  const own = await (await page.request.get("/api/merchant/restaurant")).json();
  const code = own.restaurant.restaurantCode;
  expect(code).toMatch(/^R[A-Za-z0-9]{8}$/);
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
  expect((await page.request.get(chicken.imageUrl)).status()).toBe(200);
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
  await page.getByRole("link", { name: /^(填写|编辑)我的要求$/ }).click();
  await page.getByRole("button", { name: "确认并返回" }).click();
  await page.getByRole("button", { name: "确认方案", exact: true }).click();
  await expect(page.getByText("饭菜已配齐", { exact: false })).toBeVisible();
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
    page.getByText("大家的要求或菜单变了", { exact: false }),
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
  await page.getByRole("link", { name: /^(填写|编辑)我的要求$/ }).click();
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
  const wontonCard = page.getByRole("article").filter({
    has: page.getByRole("heading", { name: wonton.name, exact: true }),
  });
  await page.getByRole("button", { name: "主食", exact: true }).click();
  await wontonCard
    .getByRole("button", { name: "增加" + wonton.name, exact: true })
    .click();
  await expect(
    wontonCard.getByLabel(wonton.name + "份数", { exact: true }),
  ).toHaveValue("2");
  await page.getByRole("button", { name: "查看已选想吃", exact: true }).click();
  const selected = page.getByRole("region", { name: "已选想吃清单" });
  await expect(
    selected.locator("li").filter({ hasText: wonton.name }),
  ).toBeVisible();
  await expect(
    selected.locator("li").filter({ hasText: drink.name }),
  ).toBeVisible();
  await selected
    .getByRole("button", { name: "取消想吃" + drink.name, exact: true })
    .click();
  await expect(
    selected.locator("li").filter({ hasText: drink.name }),
  ).toHaveCount(0);
  await page.getByRole("button", { name: "饮品", exact: true }).click();
  const drinkCard = page.getByRole("article").filter({
    has: page.getByRole("heading", { name: drink.name, exact: true }),
  });
  await expect(
    drinkCard.getByRole("button", { name: "想吃这道", exact: true }),
  ).toHaveAttribute("aria-pressed", "false");
  await selected
    .getByRole("button", { name: "收起已选想吃", exact: true })
    .click();
  await expect(selected).toHaveCount(0);
  await drinkCard
    .getByRole("button", { name: "想吃这道", exact: true })
    .click();
  await page.getByRole("button", { name: "查看已选想吃", exact: true }).click();
  await page.setViewportSize({ width: 320, height: 700 });
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBeTruthy();
  await expect(
    page.getByRole("button", { name: "完成选择", exact: true }),
  ).toBeInViewport();
  await page.screenshot({ path: "/tmp/juxiaobao-selected-wishes.png" });
  await page.setViewportSize({ width: 393, height: 852 });
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
    path: "/tmp/juxiaobao-preferences-simple.png",
    fullPage: true,
  });
  await page.setViewportSize({ width: 320, height: 700 });
  const submit = page.getByRole("button", { name: "确认并返回" });
  await expect(submit).toBeInViewport();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBeTruthy();
  await submit.click();
  await page.getByRole("button", { name: "确认方案", exact: true }).click();
  await expect(page.getByText("饭菜已配齐", { exact: false })).toBeVisible();
  const state = await (
    await page.request.get(
      "/api/sessions/" + page.url().split("/s/")[1].split("/")[0],
    )
  ).json();
  expect(
    state.recommendation.draft.items.some(
      (i: any) => i.name.includes("馄饨") || i.name.includes("混沌"),
    ),
  ).toBeTruthy();
  expect(
    state.recommendation.draft.items.some((i: any) => i.name === "米饭"),
  ).toBeFalsy();
  expect(
    state.self.preferences.wantedExtras.find((w: any) => w.dishId === wonton.id)
      ?.quantity,
  ).toBe(2);
  expect(
    state.recommendation.draft.items.find((i: any) => i.itemId === wonton.id)
      ?.quantity,
  ).toBe(2);
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
  await expect(page.getByRole("alert")).toContainText("密码太短");
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
  await page.getByLabel("食量", { exact: true }).focus();
  await page.keyboard.press("End");
  await page.keyboard.press("ArrowLeft");
  await page.getByRole("button", { name: "香菜", exact: true }).click();
  await expect(
    page.locator(".preference-label").filter({ hasText: /^常吃$/ }),
  ).toBeVisible();
  await page.getByRole("button", { name: "＋ 添加常吃", exact: true }).click();
  await page.getByLabel("其他常吃的食物").fill("西兰花");
  await page.getByLabel("其他常吃的食物").press("Enter");
  await expect(
    page.getByRole("button", { name: "西兰花", exact: true }),
  ).toHaveAttribute("aria-pressed", "true");
  await page.getByRole("button", { name: "保存为我的默认设置" }).click();
  await expect(page.getByRole("status")).toContainText("已保存");
  await page.getByRole("button", { name: "退出账号" }).click();
  await expect(
    page.getByRole("button", { name: "登录", exact: true }),
  ).toBeVisible();
  await page.getByLabel("密码", { exact: true }).fill("audit-password-123");
  await page.getByRole("button", { name: "登录", exact: true }).click();
  await expect(page.getByLabel("食量", { exact: true })).toHaveValue("2");
  await expect(
    page.getByRole("button", { name: "香菜", exact: true }),
  ).toHaveAttribute("aria-pressed", "true");
  await page.reload();
  await expect(page.getByLabel("食量", { exact: true })).toHaveValue("2");
  await expect(
    page.getByRole("button", { name: "西兰花", exact: true }),
  ).toHaveAttribute("aria-pressed", "true");
  await page.getByRole("button", { name: "西兰花", exact: true }).click();
  await page.getByRole("button", { name: "保存为我的默认设置" }).click();
  await expect(page.getByRole("status")).toContainText("已保存");
  await page.reload();
  await expect(
    page.getByRole("button", { name: "西兰花", exact: true }),
  ).toHaveCount(0);
  await page.getByRole("button", { name: "← 返回原页面" }).click();
  await expect(page).toHaveURL(/\/r\/LAOXIANGJI$/);
});

test("recover entry, invite clearly, edit from members and open visual results", async ({
  page,
  browser,
}) => {
  await page.setViewportSize({ width: 393, height: 852 });
  await page.goto("/r/DOESNOTEXIST");
  await expect(
    page.getByRole("heading", { name: "没有找到这家餐馆" }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "重试", exact: true }),
  ).toHaveCount(0);
  await page.getByRole("link", { name: "回首页重新输入" }).click();
  await expect(
    page.getByRole("link", { name: "我的", exact: true }),
  ).toHaveCount(1);
  await page.getByLabel("或输入餐馆码 / 聚餐码").fill("MISSING");
  await page.getByRole("button", { name: "进入", exact: true }).click();
  await expect(page.getByRole("alert")).toContainText("没有找到");
  await expect(page).toHaveURL(/\/$/);
  await page.getByLabel("或输入餐馆码 / 聚餐码").fill("laoxiangji");
  await page.getByRole("button", { name: "进入", exact: true }).click();
  await page.getByLabel("用餐人数").fill("2");
  await page.getByRole("button", { name: "创建聚餐局" }).click();
  await expect(page).toHaveURL(/\/s\/J[A-Za-z0-9]{6}$/);
  const roomCode = page.url().split("/s/")[1];
  const settings = page.locator(".table-settings");
  await settings.locator("summary").click();
  await expect(
    settings.getByRole("button", { name: "确定", exact: true }),
  ).toHaveCount(0);
  await settings.getByLabel("人数", { exact: true }).fill("3");
  await settings.getByRole("button", { name: "取消", exact: true }).click();
  await expect(settings).not.toHaveAttribute("open");
  await expect(settings.locator("summary")).toContainText("2 人用餐");
  await settings.locator("summary").click();
  await expect(settings.getByLabel("人数", { exact: true })).toHaveValue("2");
  await settings.getByLabel("人均预算（元）", { exact: true }).fill("40");
  await settings.getByRole("button", { name: "确定", exact: true }).click();
  await expect(settings).not.toHaveAttribute("open");
  await expect(settings.locator("summary")).toContainText("人均 ¥40.00");
  await settings.locator("summary").click();
  await settings.getByLabel("人均预算（元）", { exact: true }).fill("");
  await settings.getByRole("button", { name: "确定", exact: true }).click();
  await expect(settings.locator("summary")).toContainText("预算不限");
  await expect(page.locator(".room-tabs")).toHaveCount(0);
  await page.getByRole("button", { name: "邀请同行人", exact: true }).click();
  const invite = page.getByRole("dialog", { name: "邀请同行人" });
  await expect(invite).toBeVisible();
  const qr = await invite.getByAltText("聚餐局邀请二维码").boundingBox();
  expect(qr).toBeTruthy();
  expect(Math.abs(qr!.x + qr!.width / 2 - 393 / 2)).toBeLessThan(3);
  const input = await invite.getByLabel("邀请链接").boundingBox();
  const copy = await invite
    .getByRole("button", { name: "复制链接" })
    .boundingBox();
  expect(
    Math.abs(input!.y + input!.height / 2 - copy!.y - copy!.height / 2),
  ).toBeLessThan(3);
  await page.screenshot({ path: "/tmp/juxiaobao-invite-redesign.png" });
  await page.keyboard.press("Escape");
  await expect(invite).not.toBeVisible();
  await expect(
    page.getByRole("button", { name: "邀请同行人", exact: true }),
  ).toBeFocused();
  await page.getByRole("link", { name: "填写我的要求" }).click();
  await expect(
    page.getByRole("button", { name: "整理文字里的要求" }),
  ).toHaveCount(0);
  await expect(
    page.getByRole("slider", { name: "食量", exact: true }),
  ).toBeVisible();
  await page.getByRole("slider", { name: "接受辣度" }).focus();
  await page.keyboard.press("End");
  await page.getByRole("button", { name: "＋ 其他", exact: true }).click();
  await page.getByLabel("其他不吃的食物").fill("香椿");
  await page.getByLabel("其他不吃的食物").press("Enter");
  await expect(
    page.getByRole("button", { name: "香椿", exact: true }),
  ).toHaveAttribute("aria-pressed", "true");
  await expect(page.getByLabel("其他不吃的食物")).toHaveCount(0);
  await page.getByLabel("还有想说的？").fill("今天想清淡一点");
  await page.screenshot({
    path: "/tmp/juxiaobao-preferences-redesign.png",
    fullPage: true,
  });
  await page.getByRole("button", { name: "确认并返回" }).click();
  await page
    .getByRole("button", { name: "填写同行人 A的要求", exact: true })
    .click();
  const companion = page.getByRole("dialog", { name: "帮同行人填写" });
  await companion.getByLabel("称呼").fill("同行人 A");
  await companion.getByLabel("还有想说的？").fill("同行人想喝汤");
  await companion
    .getByRole("button", { name: "＋ 菜单选菜", exact: true })
    .click();
  const picker = page.getByRole("dialog", { name: "为同行人选菜" });
  await expect(picker).toBeVisible();
  await picker.getByRole("button", { name: "汤", exact: true }).click();
  const chosenName = await picker.locator(".menu-dish h2").first().innerText();
  await picker
    .getByRole("button", { name: "想吃这道", exact: true })
    .first()
    .click();
  await picker.getByRole("button", { name: "完成选择", exact: true }).click();
  await expect(companion.getByLabel("称呼")).toHaveValue("同行人 A");
  await expect(companion.getByLabel("还有想说的？")).toHaveValue(
    "同行人想喝汤",
  );
  await expect(
    companion.getByRole("button", {
      name: "移除想吃" + chosenName,
      exact: true,
    }),
  ).toBeVisible();
  await companion.getByRole("button", { name: "保存同行人要求" }).click();
  await expect(companion).not.toBeVisible();
  await expect(page.locator(".dining-members li")).toHaveCount(2);
  await page
    .getByRole("button", { name: "修改同行人 A的要求", exact: true })
    .click();
  const editCompanion = page.getByRole("dialog", { name: "编辑同行人的要求" });
  await expect(
    editCompanion.getByRole("button", {
      name: "移除想吃" + chosenName,
      exact: true,
    }),
  ).toBeVisible();
  await editCompanion
    .getByRole("button", { name: "取消", exact: true })
    .click();
  await page.getByRole("link", { name: "编辑我的要求", exact: true }).click();
  await expect(
    page.getByRole("button", { name: "移除想吃" + chosenName, exact: true }),
  ).toHaveCount(0);
  await page.getByRole("button", { name: "确认并返回", exact: true }).click();
  await page.screenshot({
    path: "/tmp/juxiaobao-room-redesign.png",
    fullPage: true,
  });
  // Delay the completed snapshot to exercise a real loading state under network latency.
  await page.routeWebSocket("**/ws", (ws) => {
    const server = ws.connectToServer();
    server.onMessage((message) => {
      const m = JSON.parse(String(message));
      if (m.type === "room_state" && m.payload.recommendation && !m.payload.job)
        setTimeout(() => ws.send(message), 700);
      else ws.send(message);
    });
    ws.onMessage((message) => server.send(message));
  });
  await page.reload();
  await page.getByRole("button", { name: "确认方案", exact: true }).click();
  await expect(page.locator(".working-panel")).toBeVisible();
  await expect(page).toHaveURL(new RegExp("/s/" + roomCode + "/result$"));
  await expect(page.locator(".result-dish")).not.toHaveCount(0);
  await expect
    .poll(() =>
      page
        .locator(".result-dish img")
        .first()
        .evaluate((img: HTMLImageElement) => img.naturalWidth),
    )
    .toBeGreaterThan(0);
  await page.screenshot({
    path: "/tmp/juxiaobao-result-redesign.png",
    fullPage: true,
  });
  await page.setViewportSize({ width: 320, height: 720 });
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBeTruthy();
  await page.getByRole("link", { name: "← 返回这一桌" }).click();
  const guest = await browser.newContext();
  const g = await guest.newPage();
  await g.goto("/");
  await g.getByLabel("或输入餐馆码 / 聚餐码").fill(roomCode.toLowerCase());
  await g.getByRole("button", { name: "进入", exact: true }).click();
  await expect(g).toHaveURL(new RegExp("/s/" + roomCode + "$"));
  await expect(g.locator(".dining-members li")).toHaveCount(3);
  await guest.close();
});

test("floating conversation stays open, preserves page position and handles replies and edits", async ({
  page,
}) => {
  await page.setViewportSize({ width: 393, height: 852 });
  await page.route("**/api/capabilities", (route) =>
    route.fulfill({ json: { aiEnabled: true } }),
  );
  let latest: any,
    round = 0;
  await page.routeWebSocket("**/ws", (ws) => {
    const server = ws.connectToServer();
    server.onMessage((message) => {
      const m = JSON.parse(String(message));
      if (m.type === "room_state") latest = m;
      ws.send(message);
    });
    ws.onMessage((message) => {
      const m = JSON.parse(String(message));
      if (m.type !== "chat_message") {
        server.send(message);
        return;
      }
      round++;
      const next = structuredClone(latest);
      const job = { id: "ui-chat", status: "inProgress", text: m.payload.text };
      ws.send(
        JSON.stringify({
          type: "recommendation_started",
          requestId: m.requestId,
          payload: job,
        }),
      );
      next.payload.job = job;
      ws.send(JSON.stringify(next));
      setTimeout(() => {
        next.payload.job = null;
        next.payload.messages.push({
          id: "u" + round,
          role: "user",
          content: m.payload.text,
        });
        next.payload.messages.push({
          id: "a" + round,
          role: "agent",
          content:
            round === 1 ? "你好！想了解哪道菜？" : "米饭加了一份，其他菜照旧。",
        });
        if (round === 2) {
          const rice = next.payload.recommendation.draft.items.find(
            (i: any) => i.name === "米饭",
          );
          rice.quantity++;
          next.payload.recommendation.draft.totalFen += rice.unitPriceFen;
        }
        latest = next;
        ws.send(JSON.stringify(next));
      }, 350);
    });
  });
  await page.goto("/r/LAOXIANGJI");
  await page.getByLabel("用餐人数").fill("4");
  await page.getByRole("button", { name: "创建聚餐局" }).click();
  await page.getByRole("link", { name: "填写我的要求", exact: true }).click();
  await page.getByRole("button", { name: "确认并返回" }).click();
  await page.getByRole("button", { name: "确认方案", exact: true }).click();
  await expect(page).toHaveURL(/\/result$/);
  await page.evaluate(() => window.scrollTo(0, 400));
  const before = await page.evaluate(() => window.scrollY);
  expect(before).toBeGreaterThan(100);
  await page.getByRole("button", { name: "找点菜员聊聊" }).click();
  const chat = page.getByRole("dialog", { name: "点菜员对话" });
  await expect(chat).toBeVisible();
  await expect(
    page.getByRole("button", { name: "找点菜员聊聊", exact: true }),
  ).toHaveCount(0);
  const box = await chat.boundingBox();
  expect(box!.y + box!.height).toBeGreaterThan(810);
  expect(box!.y + box!.height).toBeLessThanOrEqual(852);
  await chat.getByLabel("和点菜员说说").fill("你好");
  await chat.getByRole("button", { name: "发送", exact: true }).click();
  await expect(
    chat.getByText("你好！想了解哪道菜？", { exact: true }),
  ).toBeVisible();
  await expect(chat).toBeVisible();
  expect(
    Math.abs((await page.evaluate(() => window.scrollY)) - before),
  ).toBeLessThan(20);
  await chat.getByLabel("和点菜员说说").fill("米饭加一份");
  await chat.getByRole("button", { name: "发送", exact: true }).click();
  await expect(
    chat.getByText("米饭加了一份，其他菜照旧。", { exact: true }),
  ).toBeVisible();
  await expect(chat).toBeVisible();
  expect(
    Math.abs((await page.evaluate(() => window.scrollY)) - before),
  ).toBeLessThan(20);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
  ).toBeTruthy();
  await page.screenshot({ path: "/tmp/juxiaobao-floating-chat.png" });
  await chat.getByRole("button", { name: "收起点菜员" }).click();
  await expect(chat).not.toBeVisible();
  await expect(
    page.getByRole("button", { name: "找点菜员聊聊", exact: true }),
  ).toBeVisible();
});

test("default demo merchant can sign in and manage the sample restaurant", async ({
  page,
}) => {
  await page.goto("/admin/");
  await page.getByLabel("账号", { exact: true }).fill("admin");
  await page.getByLabel("密码", { exact: true }).fill("88888888");
  await page.getByRole("button", { name: "登录", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "老乡鸡", exact: true }),
  ).toBeVisible();
  await expect(page.locator(".merchant-dish-grid .menu-dish")).not.toHaveCount(
    0,
  );
  await page.getByRole("button", { name: "餐馆入口", exact: true }).click();
  await expect(
    page.getByRole("link", { name: /\/r\/LAOXIANGJI$/ }),
  ).toBeVisible();
  await page.reload();
  await expect(
    page.getByRole("heading", { name: "老乡鸡", exact: true }),
  ).toBeVisible();
});

test("home scan entry toggles camera off without a separate stop button or cancellation error", async ({
  page,
}) => {
  await page.addInitScript(() => {
    const streams: MediaStream[] = [];
    Object.defineProperty(window, "scanTestStreams", { value: streams });
    Object.defineProperty(navigator, "mediaDevices", {
      value: {
        getUserMedia: async () => {
          const canvas = document.createElement("canvas");
          canvas.width = canvas.height = 120;
          canvas.getContext("2d")!.fillRect(0, 0, 120, 120);
          const stream = canvas.captureStream(1);
          streams.push(stream);
          return stream;
        },
      },
    });
  });
  await page.goto("/");
  const scan = page.locator(".scan-entry");
  for (let round = 0; round < 2; round++) {
    await scan.click();
    await expect(scan).toHaveAttribute("aria-expanded", "true");
    await expect(page.locator(".scanner video")).toBeVisible();
    await expect(
      page.getByRole("button", { name: "停止扫码", exact: true }),
    ).toHaveCount(0);
    await expect
      .poll(() => page.evaluate(() => (window as any).scanTestStreams.length))
      .toBe(round + 1);
    await scan.click();
    await expect(page.locator(".scanner")).toHaveCount(0);
    await expect(scan).toHaveAttribute("aria-expanded", "false");
    await expect(page.getByRole("alert")).toHaveCount(0);
    await expect
      .poll(() =>
        page.evaluate(() =>
          (window as any).scanTestStreams.every((stream: MediaStream) =>
            stream.getTracks().every((track) => track.readyState === "ended"),
          ),
        ),
      )
      .toBe(true);
  }
  await expect(page.getByLabel("或输入餐馆码 / 聚餐码")).toBeEnabled();
});

test("two members receive their separately chosen noodles and wonton staples", async ({
  browser,
}) => {
  const host = await browser.newContext();
  const guest = await browser.newContext();
  const h = await host.newPage();
  const g = await guest.newPage();
  await h.goto("/r/LAOXIANGJI");
  await h.getByLabel("用餐人数").fill("2");
  await h.getByRole("button", { name: "创建聚餐局" }).click();
  await expect(h).toHaveURL(/\/s\/[A-Za-z0-9]+$/);
  const room = h.url();
  const code = room.split("/s/")[1];
  await h.getByRole("link", { name: "填写我的要求", exact: true }).click();
  await h.getByRole("button", { name: "面条", exact: true }).click();
  await h.getByRole("button", { name: "确认并返回", exact: true }).click();
  await g.goto(room);
  await g.getByRole("link", { name: "填写我的要求", exact: true }).click();
  await g.getByRole("button", { name: "馄饨", exact: true }).click();
  await g.getByRole("button", { name: "确认并返回", exact: true }).click();
  await expect(h.getByText("2 / 2 人已填写", { exact: false })).toBeVisible();
  await h.getByRole("button", { name: "确认方案", exact: true }).click();
  await expect(h).toHaveURL(/\/result$/);
  const state = await (await h.request.get(`/api/sessions/${code}`)).json();
  const guestState = await (
    await g.request.get(`/api/sessions/${code}`)
  ).json();
  const servings = state.recommendation.draft.mealMembers;
  const noodles = servings.find(
    (member: any) => member.memberId === state.self.id,
  )?.stapleDishId;
  const wonton = servings.find(
    (member: any) => member.memberId === guestState.self.id,
  )?.stapleDishId;
  expect(noodles).toBeTruthy();
  expect(wonton).toBeTruthy();
  expect(noodles).not.toBe(wonton);
  const menu = await (
    await h.request.get("/api/restaurants/LAOXIANGJI/menu")
  ).json();
  expect(
    menu.mealMetadata.find((fact: any) => fact.dishId === noodles)?.stapleKind,
  ).toBe("noodles");
  expect(menu.dishes.find((dish: any) => dish.id === wonton)?.name).toMatch(
    /馄饨|混沌/,
  );
  expect(
    state.recommendation.draft.items.some(
      (item: any) => item.itemId === noodles,
    ),
  ).toBe(true);
  expect(
    state.recommendation.draft.items.some(
      (item: any) => item.itemId === wonton,
    ),
  ).toBe(true);
  await host.close();
  await guest.close();
});

test("consumer and merchant switch in both directions while retaining independent logins", async ({
  page,
}) => {
  await page.setViewportSize({ width: 320, height: 720 });
  await page.goto("/account");
  await expect(
    page.getByRole("link", { name: "切换到商家端 →", exact: true }),
  ).toBeVisible();
  const login = "switch-" + Date.now();
  expect(
    (
      await page.request.post("/api/user/register", {
        data: { login, password: "switch-password-123" },
      })
    ).ok(),
  ).toBe(true);
  expect(
    (
      await page.request.post("/api/user/login", {
        data: { login, password: "switch-password-123" },
      })
    ).ok(),
  ).toBe(true);
  await page.reload();
  await expect(
    page.getByRole("heading", { name: login, exact: true }),
  ).toBeVisible();
  await page.getByRole("link", { name: "切换到商家端 →", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "商家登录", exact: true }),
  ).toBeVisible();
  await page.getByLabel("账号", { exact: true }).fill("admin");
  await page.getByLabel("密码", { exact: true }).fill("88888888");
  await page.getByRole("button", { name: "登录", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "老乡鸡", exact: true }),
  ).toBeVisible();
  await page.getByRole("link", { name: "切换到用户端", exact: true }).click();
  await page.getByRole("link", { name: "我的", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: login, exact: true }),
  ).toBeVisible();
  await page.getByRole("link", { name: "切换到商家端 →", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "老乡鸡", exact: true }),
  ).toBeVisible();
  await page.getByRole("button", { name: "退出商家账号", exact: true }).click();
  await page.getByRole("link", { name: "切换到用户端", exact: true }).click();
  await page.getByRole("link", { name: "我的", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: login, exact: true }),
  ).toBeVisible();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
});

test("Cangjie production server displays the home background and bowl brand icon", async ({
  page,
}) => {
  await page.goto("http://127.0.0.1:8095/");
  await expect(page.locator(".brand")).toContainText("聚小宝");
  const icon = page.locator("img.brand-symbol");
  await expect
    .poll(() => icon.evaluate((image: HTMLImageElement) => image.naturalWidth))
    .toBeGreaterThan(0);
  const iconURL = await icon.getAttribute("src");
  const background = await page
    .locator(".home-welcome")
    .evaluate((element) => getComputedStyle(element).backgroundImage);
  const backgroundURL = background.match(/url\(["']?([^"')]+)["']?\)/)?.[1];
  expect(backgroundURL).toBeTruthy();
  for (const path of [backgroundURL!, iconURL!]) {
    const response = await page.request.get(new URL(path, page.url()).href);
    expect(response.status()).toBe(200);
    expect(response.headers()["content-type"]).toBe("image/png");
    expect([...(await response.body()).subarray(0, 8)]).toEqual([
      137, 80, 78, 71, 13, 10, 26, 10,
    ]);
  }
  await page.screenshot({ path: "/tmp/juxiaobao-real-backend-home.png" });
  await page.setViewportSize({ width: 320, height: 852 });
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
  await page.screenshot({ path: "/tmp/juxiaobao-real-backend-mobile.png" });
  await page.goto("http://127.0.0.1:8095/admin/");
  await expect(page.locator(".brand")).toContainText("聚小宝 · 餐馆工作台");
});

test("a fifth member joining four filled seats increases people once and preserves existing preferences", async ({
  browser,
}) => {
  const host = await browser.newContext();
  const guest = await browser.newContext();
  const h = await host.newPage();
  const g = await guest.newPage();
  await h.goto("/r/LAOXIANGJI");
  await h.getByLabel("用餐人数").fill("4");
  await h.getByRole("button", { name: "创建聚餐局" }).click();
  await expect(h).toHaveURL(/\/s\/[A-Za-z0-9]+$/);
  const room = h.url();
  const code = room.split("/s/")[1];
  await h.getByRole("link", { name: "填写我的要求", exact: true }).click();
  await h.getByRole("button", { name: "确认并返回", exact: true }).click();
  for (const letter of ["A", "B", "C"]) {
    await h
      .getByRole("button", { name: `填写同行人 ${letter}的要求`, exact: true })
      .click();
    const form = h.getByRole("dialog", { name: "帮同行人填写", exact: true });
    await form
      .getByRole("button", { name: "保存同行人要求", exact: true })
      .click();
    await expect(form).not.toBeVisible();
  }
  await expect(h.getByText("4 / 4 人已填写", { exact: true })).toBeVisible();
  const before = await (await h.request.get(`/api/sessions/${code}`)).json();
  await g.goto(room);
  await expect(g.locator(".dining-members li")).toHaveCount(5);
  await expect(h.getByText("4 / 5 人已填写", { exact: true })).toBeVisible();
  const joined = await (await g.request.get(`/api/sessions/${code}`)).json();
  expect(joined.session.people).toBe(5);
  expect(new Set(joined.members.map((member: any) => member.id)).size).toBe(5);
  for (const member of before.members) {
    const existing = joined.members.find(
      (candidate: any) => candidate.id === member.id,
    );
    expect(existing.submitted).toBe(true);
    expect(existing.preferences).toEqual(member.preferences);
  }
  await g.reload();
  await expect(g.locator(".dining-members li")).toHaveCount(5);
  const rejoined = await (await g.request.get(`/api/sessions/${code}`)).json();
  expect(rejoined.session.people).toBe(5);
  expect(rejoined.self.id).toBe(joined.self.id);
  await expect(h.getByText("4 / 5 人已填写", { exact: true })).toBeVisible();
  await host.close();
  await guest.close();
});
