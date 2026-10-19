# P3 用户端与商家端界面 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用正式页面完成主页进店、协作点菜、可选账号和商家管理，规则模式即可全程使用。

**Architecture:** Vue多入口分别构建用户端和商家端；共享类型/API，业务状态来自仓颉HTTP/WS。仅本人未提交输入作为本地草稿，页面切换和账号跳转不重建房间；旧原型不作为正式状态层。

**Tech Stack:** Vue 3、Vite、TypeScript、Vue Router、Vitest、Playwright、ZXing浏览器扫码、二维码生成库；依赖在首次安装时核对Node兼容性并锁定package-lock。

**Spec:** [设计文档](../specs/2026-10-16-group-dining-agent-design.md)；依赖 [P1](2026-10-17-platform-catalog-plan.md)/[P2](2026-10-17-room-rules-plan.md)，接口见[总计划](2026-10-17-group-dining-implementation.md)。

**两人归属：** C端和商家端全部前端均由我负责，包括注册/登录/默认设置和菜单管理页面；另一位成员仅交付这些页面调用的后端API。前端按共同DTO开发，正式验收必须接对方真实服务，不能把mock接口当后端交付。

## Global Constraints

- 继承总计划全部约束；不改写 `docs/prototypes/` 或拿单浏览器模拟替代协作。
- “主页只承担入口职责”；菜单在具体餐馆内，账号可选。
- “建局前的菜品/套餐愿望草稿按餐馆分别保留，不跨店带入”。
- 不显示“忌口 0 违反”；展示“适合自己的菜”、填写人数和可选菜不足。
- `unknown`显示“其余食材不详”，保留已知食材；有食材限制者的uncertain不归入“适合你的菜”，不用确定冲突文案替代信息不足。筛选/覆盖结果以服务端为准。

## Review Focus

1. 相机拒绝、不可用或扫到外部链接：保留餐馆码入口，不任意跳转，T1。
2. 从菜单/账号返回，文字和菜品草稿仍在；餐馆切换不串店，T1/T2。
3. 手机刷新/断网后重连，不重复成员、不用旧推荐覆盖新快照，T2。
4. 默认设置只是预填，保存失败/登录失败不阻塞访客，T3。
5. 商家价格修改、套餐组分无效及窄屏操作：错误可见、数据不误报成功，T4。

### Task 1: 前端工程、主页、扫码与餐馆菜单

**Files:** Create `frontend/package.json`、`frontend/package-lock.json`、`frontend/tsconfig.json`、`frontend/vite.config.ts`、`frontend/vitest.config.ts`、`frontend/playwright.config.ts`、`frontend/index.html`、`frontend/admin/index.html`、`frontend/src/main.ts`、`frontend/src/admin-main.ts`、`frontend/src/router.ts`、`frontend/src/shared/contracts.ts`、`frontend/src/shared/api.ts`、`frontend/src/shared/styles.css`、`frontend/src/features/entry/{HomePage.vue,RestaurantPage.vue,scan.ts,entry.test.ts}`、`frontend/src/features/menu/{MenuPage.vue,drafts.ts,drafts.test.ts}`、`frontend/e2e/entry.spec.ts`；Modify `src/app/server.cj`。

**Interfaces:** Consumes P1餐馆/菜单HTTP；Produces `resolveEntry(value:string,origin:string): {kind:'restaurant'|'room',code:string}|null`、`scanCode(video:HTMLVideoElement): Promise<{text:string,stop:()=>void}>`、`loadDraft(key:DraftKey): Preferences`、`saveDraft(key:DraftKey,prefs:Preferences):void`。DraftKey为`restaurant:code`或`room:code:participantId`；API `getMenu(code):Promise<MenuSnapshot>`；TS DTO精确映射总计划。

`entry.spec.ts`覆盖已知+unknown显示已知食材及中文提示、仅unknown不显示“无其他食材”；仍可浏览/标记愿望，愿望不代表已确认适配。

- [ ] **Step 1 — 写失败用例。** 建立最小Vite/Vitest/Playwright配置；`entry.test.ts`断言餐馆/邀请链接分流，`expect(resolveEntry('https://other.example/r/A', origin)).toBeNull()`；`drafts.test.ts`断言A店草稿不带入B店，`expect(loadDraft(bKey).wantedDishIds).toEqual([])`；`entry.spec.ts`断言输入餐馆码进入店页、直接链接同页、进店不创建房间、菜单可标记菜/套餐及展开组分、返回仍保留。
- [ ] **Step 2 — 运行。** 在frontend目录 `npm run test -- --run src/features/entry/entry.test.ts src/features/menu/drafts.test.ts`、`npm run test:e2e -- entry.spec.ts`，确认对应行为失败；测试脚本在Step1配置，不以缺脚本报错冒充失败。
- [ ] **Step 3 — 实现页面。** 主页突出扫码、餐馆码和账号入口；扫码仅点击后申请权限，页面卸载停止摄像头，失败可改输码；使用ZXing解码，生成二维码使用成熟库。API错误可重试。Vite输出到根web/和web/admin/，仓颉分别提供SPA回退，API404保持JSON；深链刷新可用。目录外部二维码不导航。
- [ ] **Step 4 — 验证。** 上述用例通过，加测相机拒绝、无效餐馆、网络重试、扫码邀请生成正确房间目标路径（实际进入同一房间由T2验证）；`npm run typecheck`、`npm run build`通过，产物由仓颉托管后直接刷新餐馆路径仍正确。
- [ ] **Step 5 — 保存检查点。** `git diff --check`；提交本任务源码、配置和lock，排除web构建产物，说明 `feat: add home restaurant entries and menu browsing`。

### Task 2: 建局、个人输入、多人同步与推荐页面

**Files:** Create `frontend/src/features/room/{RoomPage.vue,room.ts,room.test.ts,InvitePanel.vue,CompanionForm.vue}`、`frontend/src/features/preferences/{PreferencesPage.vue,preferences.ts,preferences.test.ts}`、`frontend/src/features/recommendation/{RecommendationPage.vue,RecommendationItems.vue}`、`frontend/src/shared/socket.ts`、`frontend/e2e/dining.spec.ts`、`frontend/e2e/recovery.spec.ts`；Modify `frontend/src/router.ts`、`frontend/src/features/menu/MenuPage.vue`、`frontend/src/features/entry/RestaurantPage.vue`。

**Interfaces:** Consumes P2 HTTP/WS；Produces `createRoom(input:CreateSessionInput):Promise<RoomSnapshot>`、`connectRoom(code:string,onState:(s:RoomSnapshot)=>void): RoomConnection`，连接对象提供`send(type:string,payload:unknown):Promise<void>`/`close():void`；`submitPreferences(prefs:Preferences):Promise<void>`。createRoom重试复用同requestId；服务端快照是已提交状态唯一来源。

`dining.spec.ts`覆盖：无食材限制者可看到含unknown的入选菜且显示提示；素食/不吃成员不将该菜计入适配；套餐其他完整适配组分仍展示；已有过敏提交时unknown菜及相关套餐不入选，未选愿望可解释；移除/新增unknown后旧结果失效。0道仅因信息不足时明确写“食材不完整，暂不计入适合你的菜”，不声称确定含其不吃食材。

- [ ] **Step 1 — 写失败用例。** `room.test.ts`断言重连取得最新快照，`expect(rejoined.self.id).toBe(original.self.id)`，请求重试不重复建局；`preferences.test.ts`断言未保存不算提交、结构化限制不能被文字覆盖、修改限制后冲突愿望取消并解释。`dining.spec.ts`用两个浏览器context断言host未填即可邀请、guest先提交、文字/菜品跨菜单保留、套餐按组分展示个人选择，`expect(guestSnapshot.session.id).toBe(hostSnapshot.session.id)`。
- [ ] **Step 2 — 运行。** `npm run test -- --run src/features/room/room.test.ts src/features/preferences/preferences.test.ts`、`npm run test:e2e -- dining.spec.ts recovery.spec.ts`，确认预期失败。
- [ ] **Step 3 — 实现主流程。** 建局/连接前调用`POST /api/visitor/session`确保访客cookie，账号可有可无；邀请含房间链接/短码/二维码；过敏独立展开，快捷点选+可选200字。补充同行人入口次级且不强制昵称头像。WS指数退避，重连先join取快照再解锁操作；不把已发送但未确认的旧变更静默重放。推荐展示套餐售价/额外单点/总价/适合本人实际菜，1道与0道明确提示；确认/重开按角色和canConfirm控制，服务器拒绝时刷新快照。快捷调整沿用已校验规则操作，P4接入自由对话。
- [ ] **Step 4 — 验证。** 上述测试通过；`recovery.spec.ts`覆盖刷新与断网不重复成员、menuVersion变化后旧结果不能确认、closed重开同房间、草稿不计已填写、未齐仅保留、0道无完整确认按钮；320px与桌面不横向溢出。无密钥下完整规则流程可用。
- [ ] **Step 5 — 保存检查点。** `git diff --check`；提交本任务文件，说明 `feat: add collaborative dining and rule result pages`。

### Task 3: 账号页、默认设置与原路返回

**Files:** Create `frontend/src/features/account/{AccountPage.vue,DefaultSettingsForm.vue,account.ts,account.test.ts}`、`frontend/e2e/account.spec.ts`；Modify `frontend/src/router.ts`、`frontend/src/features/entry/HomePage.vue`、`frontend/src/features/room/RoomPage.vue`、`frontend/src/features/preferences/PreferencesPage.vue`。

**Interfaces:** Consumes P1用户账号/默认设置HTTP；Produces `loadAccount():Promise<UserView|null>`、`saveDefaults(settings:UserDefaultSettings):Promise<UserDefaultSettings>`、`openAccount(returnTo:string):void`。returnTo仅允许应用内路径；本局仅在主动应用默认值/保存本局时提交WS。

- [ ] **Step 1 — 写失败用例。** `account.test.ts`：默认值不含本餐愿望/文字，不覆盖已有草稿，账号失败返回访客态；`account.spec.ts`：主页登录保存默认值后回主页，房间中途登录后`expect(after.self.id).toBe(before.self.id)`、`expect(after.self.draft.note).toBe(before.self.draft.note)`；默认值预填但未提交，主动保存默认才影响新局，退出不删除本局提交。
- [ ] **Step 2 — 运行。** `npm run test -- --run src/features/account/account.test.ts`、`npm run test:e2e -- account.spec.ts`，确认失败。
- [ ] **Step 3 — 实现。** 主页账号入口显示“登录 / 注册”或“我的”；设置仅登录后读写。页面提示“已带入默认设置”，本局默认只改本局；主动保存长期默认项明确反馈。返回来源页面复用T1草稿，登录状态刷新不重建房间；补充同行人表单不应用本人默认值。
- [ ] **Step 4 — 验证。** 单测和e2e通过，加测默认值读取失败可手填、保存失败显示未写入账号且本局有效、访客不被登录弹窗拦截、不同餐馆切换和账号返回不串草稿。
- [ ] **Step 5 — 保存检查点。** `git diff --check`；提交本任务文件，说明 `feat: add optional account and personal defaults pages`。

### Task 4: 商家页面、餐馆二维码与端到端菜单联动

**Files:** Create `frontend/src/features/admin/{AdminApp.vue,LoginPage.vue,RestaurantPage.vue,MenuEditor.vue,DishForm.vue,SetMealForm.vue,EntryPanel.vue}`、`frontend/e2e/merchant.spec.ts`；Modify `frontend/src/admin-main.ts`、`frontend/src/shared/api.ts`。

**Interfaces:** Consumes P1商家/目录API；Produces商家独立页面、餐馆链接/码/二维码展示与保存；表单DTO分别为DishInput/SetMealInput，价格输入元后转换priceFen，不新增spec外业务字段。

食材表单提供可选“仍有不明食材”，和具体食材共用ingredients数组存unknown；仅未知也可保存。`merchant.spec.ts`验证编辑回显、保存/查询不丢标记、取消标记且明确补全食材后菜单版本变更；不另建完整性/过敏原状态表单。

- [ ] **Step 1 — 写失败用例。** `merchant.spec.ts`用两商家账号断言注册/登录/建店/精确字段录菜/选择同店菜组套餐，`expect(publicMenu.setMeals[0].priceFen).toBe(12800)`（输入128元）；输入空组分/quantity=0/无效价格显示错误；删除被引用菜显示409原因；餐馆二维码链接进入用户端对应店页。
- [ ] **Step 2 — 运行。** `npm run test:e2e -- merchant.spec.ts`，确认页面操作因未实现失败。
- [ ] **Step 3 — 实现。** 商家端守卫独立于C端可选登录；菜单分类与套餐分区分别维护，组分选择份数不复制菜品数据；表单写入失败保留输入。EntryPanel用服务端entry链接生成可保存二维码。菜单更新通过P2使打开的用户房间推荐失效。
- [ ] **Step 4 — 验证。** e2e通过，加测商家改价/下架时另一个用户context旧推荐失效、跨店操作拒绝、两端登录cookie不互相替代；`npm run typecheck`、`npm run test -- --run`、`npm run build`与P1/P2集成通过。
- [ ] **Step 5 — 保存检查点。** `git diff --check`；提交本任务文件，说明 `feat: add merchant menus set meals and restaurant QR`。

**阶段出口：** 不配置DeepSeek，用户端/商家端完整主流程在真实仓颉服务运行；二维码进入、真实双context协作、规则推荐、账号默认值与菜单变更联动均有证据。相机真实设备验证另记录在P4验收表，不能仅用mock宣称已验证手机扫码。
