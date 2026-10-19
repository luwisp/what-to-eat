# P1 基础服务、账号与菜单 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付能启动、持久化、认证并管理两家餐馆菜单的仓颉服务。

**Architecture:** 先验证平台，再建立模型/Repository；账号服务与目录服务共享持久化事务，路由只解析请求和调用服务。此阶段通过 HTTP 和集成测试验收，不借用模拟原型充当实现。

**Tech Stack:** Cangjie 1.2.0、匹配的 stdx、sqlite4cj / JSON、仓颉测试框架、Node 验收客户端。

**Spec:** [设计文档](../specs/2026-10-16-group-dining-agent-design.md)；共同接口见[总计划](2026-10-17-group-dining-implementation.md)。

**两人归属：** T1由我负责；T2中共享模型/校验类型与Repository接口由我负责，持久化实现/演示数据/目录查询由另一位成员负责；T3/T4模块由另一位成员负责。T2–T4涉及`src/app/server.cj`、构建锁文件、`docs/dev/contracts.md`的修改统一由我集成，对方将模块用法写入`docs/dev/backend-data.md`。文件归属与批次见[后端交接](2026-10-17-two-person-backend-handoff.md)。

## Global Constraints

- 继承总计划全部 Global Constraints、共同接口与文件边界。
- “一个账号绑定一家餐厅，MVP 简化”；C 端与商家权限隔离。
- “SQLite 存储层（sqlite4cj；兜底 JSON 文件）”；先验证，选定一个后实施，不同时维护两套业务。
- 菜品分类仅“凉菜/热菜/汤/主食/饮品”，辣度“不辣/微辣/中辣/重辣”。
- 食材数组中的`unknown`是“其余食材不详”标记，已知食材和标记可并存；保存/读取不丢失，不增加独立资料状态表。空数组按spec归一为`["unknown"]`。

## Review Focus

1. 干净的非交互 shell 能启动，SDK 环境不依赖用户终端配置：T1。
2. 持久化过程中中断或重启，不把半份写入当有效数据：T2。
3. 小数元转整数分、非法辣度和重复套餐组分：T2/T4。
4. C 端 cookie、商家 cookie、伪造 userId 不产生越权：T3/T4。
5. 被套餐引用的菜删除或下架，不能留下可推荐的悬空组分：T4。

### Task 1: 工具链、HTTP/WS 与存储可行性门禁

**Files:** Create `cjpm.toml`、`src/main.cj`、`src/app/server.cj`、`src/platform/http.cj`、`src/platform/clock.cj`、`src/platform/platform_test.cj`、`scripts/cj.sh`、`scripts/smoke-platform.mjs`、`package.json`、`package-lock.json`、`docs/dev/environment.md`、`.gitignore`。依赖解析生成 `cjpm.lock`。

**Interfaces:** Produces `startServer(config: ServerConfig): Unit`、`GET /health -> {status:"ok",sdk:"1.2.0"}`、可注入`Clock`的日历时间/单调计时与`Deadline`剩余时限；`scripts/cj.sh <cjpm 参数>` 在子 shell 加载 SDK；测试专用 WS echo 仅在测试配置启用。Node集成脚本使用锁定的`ws`测试依赖，后续可分别携带cookie。

- [x] **Step 1 — 写平台失败测试。** `PlatformTests.health`：`@Expect(response.status, 200)`、`@Expect(response.body.sdk, "1.2.0")`；`PlatformTests.wsEcho` 断言两个连接分别完成升级与收发、关闭后可重连；先建立最小 cjpm 测试包与 scripts/cj.sh 运行包装，让测试因服务未实现而失败。
- [x] **Step 2 — 确认预期失败。** `bash scripts/cj.sh test --filter 'PlatformTests.*'`；预期失败指向未实现能力，不能把缺失命令或下载错误记作测试红灯。
- [x] **Step 3 — 实现最小平台并记录选择。** 从已发现的 SDK 加载环境，配置可覆写的 SDK 路径；引入匹配 1.2.0 的 stdx 并验证 HTTP、WS、JSON 和 HTTPS 客户端。尝试 sqlite4cj 的建表/写入/重启读取；一个最小用例确认版本不兼容后记录错误，选 JSON 继续，不展开库升级工程。验证系统随机源与成熟密码散列能力，不自行设计密码算法；网络适配失败再按 spec 的社区备选验证。
- [x] **Step 4 — 运行验收。** `bash scripts/cj.sh test --filter 'PlatformTests.*'` 通过；启动服务后 `node scripts/smoke-platform.mjs` 输出 HTTP/两连接 WS/重连各项通过。记录实际 stdx 版本、链接依赖、存储选择与原始命令；仍不可运行就只报告平台阻塞，不能声称业务已可开发运行。
- [x] **Step 5 — 保存检查点。** `git diff --check`；只提交本任务文件，提交说明 `chore: verify cangjie platform on 1.2.0`。

### Task 2: 模型、金额校验、持久化与演示目录

**Files:** Create `src/model/entities.cj`、`src/model/contracts.cj`、`src/model/validation.cj`、`src/model/validation_test.cj`、`src/store/repository.cj`、`src/store/repository_test.cj`、`src/store/seed.cj`、`src/catalog/query.cj`、`src/catalog/query_test.cj`、`src/catalog/http.cj`、`data/fixtures/restaurants.json`、`docs/dev/contracts.md`；Modify `src/app/server.cj`。按 T1 结果创建 `src/store/sqlite_repository.cj` 或 `src/store/json_repository.cj`。

**Interfaces:** Consumes T1 平台；Produces 总计划的所有共享 DTO 与 `Repository.read(): DatabaseSnapshot`、`Repository.transact(change: (DatabaseSnapshot) -> Outcome<DatabaseSnapshot>): Outcome<Unit>`、`CatalogService.getMenu(restaurantCode: String): Outcome<MenuSnapshot>`。`DatabaseSnapshot` 包含 schemaVersion、账号/会话、默认设置、餐馆/菜单、房间/成员、推荐/聊天及去重记录；后续任务填充对应集合。

共享校验另提供`normalizeIngredients(values: Array<String>): Array<String>`：归一unknown大小写/首尾空白并合并重复标记，空数组/全空白转为`["unknown"]`，保留已知食材。`ValidationTests`断言`["土豆"," UNKNOWN ","unknown"] -> ["土豆","unknown"]`，`[] -> ["unknown"]`；Repository/CatalogQuery测试保存→重启→查询标记不丢失，演示数据包含已知+unknown及仅unknown样例。筛选逻辑不放进目录查询。

- [ ] **Step 1 — 写失败用例。** `ValidationTests`：`@Expect(parsedPriceFen, 1990)`（输入19.90元）、`@Expect(parsedSmallPriceFen, 1)`（输入0.01元），负价、超过两位小数、辣度4、空套餐、quantity=0 拒绝；`RepositoryTests`：`@Expect(afterFailedTransaction, beforeTransaction)`，重启后读取与写入相同；`CatalogQueryTests` 断言未知餐馆404、读取餐馆不创建房间。另创建`src/catalog/query_test.cj`承载目录查询测试。
- [ ] **Step 2 — 运行。** `bash scripts/cj.sh test --filter 'ValidationTests.*,RepositoryTests.*,CatalogQueryTests.*'`，确认断言因缺失实现失败。
- [ ] **Step 3 — 实现接口。** 模型严格映射 spec 字段，金额整数分；SQLite 用事务，JSON 用单进程写锁、同目录临时文件/同步后原子替换，损坏数据启动明确失败而非清空。目录 HTTP 返回同店菜单与版本。演示数据含2家店、主川菜馆25道完整字段菜、至少1套餐及可验证的素食/辣度/调料场景；演示账号密码由显式演示初始化配置提供，不打印到日志。
- [ ] **Step 4 — 验证。** 上述三组测试通过，并用测试临时目录验证重启、故障写入保留上个完整快照；`GET /api/restaurants/:restaurantCode/menu` 返回对应店的25菜及套餐，另一店查询不混入它们。
- [ ] **Step 5 — 保存检查点。** `git diff --check`；提交本任务文件，说明 `feat: add persisted dining models and demo catalog`。

### Task 3: 可选用户账号、商家账号与默认设置 API

**Files:** Create `src/auth/passwords.cj`、`src/auth/sessions.cj`、`src/auth/service.cj`、`src/auth/http.cj`、`src/auth/auth_test.cj`、`src/auth/defaults_test.cj`；Modify `src/app/server.cj`、`docs/dev/contracts.md`。

**Interfaces:** Consumes T2 Repository/Actor/Preferences；Produces `AuthService.register(kind: AccountKind, login: String, password: String): Outcome<AccountView>`、`login(kind,login,password): Outcome<AuthSession>`、`resolve(cookies: String): Actor`、`ensureVisitor(cookies: String): Outcome<VisitorSession>`、`logout(kind,actor): Outcome<Unit>`、`DefaultSettingsService.get(actor): Outcome<UserDefaultSettings>`、`put(actor,settings): Outcome<UserDefaultSettings>`；路由按总计划。模块提供`registerAuthRoutes(router: HttpRouter, auth: AuthService, defaults: DefaultSettingsService): Unit`，由我集成。

- [ ] **Step 1 — 写失败用例。** `AuthTests`：`@Expect(afterLogin.visitorId, beforeLogin.visitorId)`，ensureVisitor在已有cookie下幂等、不创建房间成员；同密码不同盐、错误密码拒绝、会话过期/退出失效、商家会话不授权用户默认值；`DefaultsTests`：`@Expect(guestResponse.status, 401)`，请求体伪造userId无效、仅允许默认字段，wantedDishIds/note/预算不落默认设置。
- [ ] **Step 2 — 运行。** `bash scripts/cj.sh test --filter 'AuthTests.*,DefaultsTests.*'`，确认失败。
- [ ] **Step 3 — 实现。** 使用 T1 已验证的成熟带盐慢散列实现，保存算法/参数/盐/散列并以对应测试向量验证，不用普通摘要代替密码散列。会话使用系统安全随机 token、落库过期，cookie HttpOnly/SameSite，HTTPS 时 Secure；访客与账号分离；变更请求校验同源来源。账号失败不封锁公开目录或访客入口。
- [ ] **Step 4 — 验证。** 两组测试全过；通过 HTTP 注册、登录、保存/读取默认值、退出后读默认值401，公开菜单仍200。错误响应不含密码、散列或 token。
- [ ] **Step 5 — 保存检查点。** `git diff --check`；提交本任务文件，说明 `feat: add optional user accounts and defaults`。

### Task 4: 商家餐馆、菜品和固定套餐管理 API

**Files:** Create `src/catalog/service.cj`、`src/catalog/catalog_test.cj`、`src/catalog/entry.cj`；Modify `src/catalog/http.cj`、`src/app/server.cj`、`docs/dev/contracts.md`。

**Interfaces:** Consumes T2 CatalogService、T3 Actor；Produces `CatalogService.saveRestaurant(actor, input): Outcome<Restaurant>`、`saveDish(actor,id: Option<String>,input: DishInput): Outcome<Dish>`、`deleteDish(actor,id): Outcome<Unit>`、`saveSetMeal(actor,id: Option<String>,input: SetMealInput): Outcome<SetMeal>`、`deleteSetMeal(actor,id): Outcome<Unit>`、`restaurantEntry(restaurantId,publicBaseUrl): RestaurantEntry`；`registerCatalogRoutes(router: HttpRouter, catalog: CatalogService): Unit`由我挂载。`RestaurantEntry` 为 restaurantCode/link；二维码在 P3 由该链接生成。CatalogService在提交成功且释放持久化锁后调用`onMenuCommitted(restaurantId,menuVersion)`，我在P2装配通知，不由对方导入房间服务。

食材写入调用共享归一化，不把unknown删为无效词；`CatalogMutationTests`覆盖新增/移除unknown使menuVersion递增且提交后通知，未改动的已知食材保留。套餐仍引用原菜品食材，不把未知组分复制成一份“完整”配方。

- [ ] **Step 1 — 写失败用例。** `CatalogMutationTests`：`@Expect(crossStoreResponse.status, 403)`、`@Expect(referencedDishDelete.status, 409)`、`@Expect(updatedMenuVersion, oldMenuVersion + 1)`；访客401、一商家只能建1店、短码唯一；非法数量/跨店组分拒绝、重复组分合并数量后存储、组分下架使套餐不可推荐，失败写入不递增版本。
- [ ] **Step 2 — 运行。** `bash scripts/cj.sh test --filter 'CatalogMutationTests.*'`，确认失败。
- [ ] **Step 3 — 实现。** 商家归属由会话确定；每次菜品/套餐写入同一事务更新菜单版本；套餐不复制食材、不增设可售状态字段。餐馆码稳定，不随房间TTL变化；entry链接使用明确配置的公共访问地址，不采用任意请求头拼接。
- [ ] **Step 4 — 验证。** 上述测试通过；实际 HTTP 跑建店→录菜→套餐→公开读取；服务重启后字段、归属、价格和入口链接一致。
- [ ] **Step 5 — 保存检查点。** `git diff --check`；提交本任务文件，说明 `feat: add merchant catalog and restaurant entries`。

**阶段出口：** `bash scripts/cj.sh test` 通过，真实 HTTP/WS 平台用例通过；`docs/dev/environment.md` 明确所选存储、启动方式和仍未实现的阶段。P1 不以浏览器原型模拟功能作为完成证据。
