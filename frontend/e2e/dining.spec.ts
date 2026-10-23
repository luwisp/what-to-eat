import { test, expect } from "@playwright/test";
test("browse first, preserve wishes and text, invite before filling, independent members and reconnect", async ({
  browser,
}) => {
  const host = await browser.newContext(),
    guest = await browser.newContext();
  const h = await host.newPage(),
    g = await guest.newPage();
  const errors: string[] = [];
  h.on("pageerror", (e) => errors.push(e.message));
  await h.goto("/");
  await h.getByLabel("或输入餐馆码 / 聚餐码").fill("TEST");
  await h.getByRole("button", { name: "进入", exact: true }).click();
  await expect(h.getByRole("heading", { name: "测试餐馆" })).toBeVisible();
  await h.getByRole("link", { name: "先看菜单，标记今天想吃" }).click();
  await expect(h.getByText("其余食材不详", { exact: false })).toBeVisible();
  await h.getByRole("button", { name: "想吃这道" }).first().click();
  await h.getByRole("button", { name: "完成选择" }).click();
  await h.getByLabel("用餐人数").fill("2");
  await h.getByRole("button", { name: "创建聚餐局" }).click();
  await expect(h).toHaveURL(/\/s\/[A-Za-z0-9]+$/);
  const room = h.url();
  await h.getByRole("button", { name: "邀请同行人" }).click();
  await expect(h.getByRole("dialog", { name: "邀请同行人" })).toBeVisible();
  await h.getByRole("button", { name: "关闭邀请同行人" }).click();
  await g.goto(room);
  await expect(g.locator(".dining-members li")).toHaveCount(2);
  await g.getByRole("link", { name: /^(填写|编辑)我的要求$/ }).click();
  await g.getByLabel("还有想说的？").fill("今天不想太油腻");
  await g.getByRole("button", { name: "确认并返回" }).click();
  await expect(h.getByText("1 / 2 人已填写", { exact: false })).toBeVisible();
  await h.getByRole("link", { name: /^(填写|编辑)我的要求$/ }).click();
  await expect(h.getByRole("button", { name: /^移除想吃/ })).toHaveCount(1);
  await h.getByLabel("还有想说的？").fill("我的文字草稿");
  await h.getByRole("link", { name: "看菜单，选想吃的菜 →" }).click();
  await h.getByRole("button", { name: "完成选择" }).click();
  await expect(h.getByLabel("还有想说的？")).toHaveValue("我的文字草稿");
  await h.getByRole("button", { name: "确认并返回" }).click();
  await h.getByRole("button", { name: "确认方案", exact: true }).click();
  await expect(h.getByRole("heading", { name: "这桌这样点" })).toBeVisible();
  await expect(
    h
      .locator("li .dish-description")
      .filter({ hasText: /^青椒清香，土豆爽脆。$/ }),
  ).toBeVisible();
  await h.getByRole("button", { name: "找点菜员聊聊" }).click();
  await expect(
    h.getByText("基础搭配 · 可手动调整", { exact: true }),
  ).toBeVisible();
  await h.getByRole("button", { name: "收起点菜员" }).click();
  await expect(h.getByRole("button", { name: "确认这桌方案" })).toBeEnabled();
  await h.getByRole("button", { name: "确认这桌方案" }).click();
  await expect(h.getByText("本桌已确认", { exact: false })).toBeVisible();
  await g.reload();
  await expect(g.getByText("本桌已确认", { exact: false })).toBeVisible();
  await h.getByRole("button", { name: "重开同一聚餐局" }).click();
  await expect(
    h.getByRole("button", { name: "重新搭配这一桌", exact: true }),
  ).toBeEnabled();
  expect(errors).toEqual([]);
  await host.close();
  await guest.close();
});
test("table size creates unfilled slots that are replaced by companions and guests", async ({
  page,
  browser,
}) => {
  await page.goto("/r/TEST");
  await page.getByLabel("用餐人数").fill("4");
  await page.getByRole("button", { name: "创建聚餐局" }).click();
  await expect(page).toHaveURL(/\/s\/[A-Za-z0-9]+$/);
  const room = page.url();
  const members = page.locator(".dining-members li");
  const placeholders = page.locator(".member-placeholder");
  await expect(members).toHaveCount(4);
  await expect(placeholders).toHaveCount(3);
  await expect(page.getByText("0 / 4 人已填写")).toBeVisible();

  await page.getByRole("button", { name: "填写同行人 B的要求" }).click();
  const companion = page.getByRole("dialog", { name: "帮同行人填写" });
  await expect(companion.getByLabel("称呼")).toHaveValue("同行人 B");
  await companion.getByRole("button", { name: "保存同行人要求" }).click();
  await expect(companion).not.toBeVisible();
  await expect(members).toHaveCount(4);
  await expect(placeholders).toHaveCount(2);
  await expect(page.getByText("1 / 4 人已填写")).toBeVisible();
  await expect(placeholders.filter({ hasText: "同行人 B" })).toHaveCount(0);

  const guest = await browser.newContext();
  try {
    const g = await guest.newPage();
    await g.goto(room);
    await expect(g.locator(".dining-members li")).toHaveCount(4);
    await expect(placeholders).toHaveCount(1);

    const settings = page.locator(".table-settings");
    await settings.locator("summary").click();
    await settings.getByLabel("人数", { exact: true }).fill("3");
    await settings.getByRole("button", { name: "确定", exact: true }).click();
    await expect(members).toHaveCount(3);
    await expect(placeholders).toHaveCount(0);
    await settings.locator("summary").click();
    await settings.getByLabel("人数", { exact: true }).fill("4");
    await settings.getByRole("button", { name: "确定", exact: true }).click();
    await expect(placeholders).toHaveCount(1);

    await page
      .getByRole("button", { name: "删除同行人 B", exact: true })
      .click();
    await expect(members).toHaveCount(4);
    await expect(placeholders).toHaveCount(2);
    await expect(page.getByText("0 / 4 人已填写")).toBeVisible();
    await page.setViewportSize({ width: 320, height: 720 });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
  } finally {
    await guest.close();
  }
});

test("320px layout has no horizontal overflow and external entry remains rejected", async ({
  page,
}) => {
  await page.setViewportSize({ width: 320, height: 720 });
  await page.goto("/");
  await page
    .getByLabel("或输入餐馆码 / 聚餐码")
    .fill("https://evil.example/r/TEST");
  await page.getByRole("button", { name: "进入", exact: true }).click();
  await expect(page.getByRole("alert")).toBeVisible();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
  await page.goto("/r/TEST/menu");
  await expect(page.getByRole("heading", { name: "青椒土豆" })).toBeVisible();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
});

test("camera failure preserves the manual entry route", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("button", { name: "扫描餐馆或邀请二维码" }).click();
  await expect(page.getByRole("alert")).toContainText("也可以直接输入餐馆码");
  await expect(page.getByLabel("或输入餐馆码 / 聚餐码")).toBeEnabled();
});
