# 多人聚餐点菜 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将已确认的 spec 实现为可跨设备协作、具有规则兜底和可选账号的点菜应用。

**Architecture:** 仓颉后端托管 HTTP、WebSocket 与前端静态产物；业务服务负责权限、持久化和版本检查，规则引擎独立于模型。先交付可验证的基础 API，再实现多人规则闭环、正式界面，最后接入 AI。

**Tech Stack:** Cangjie 1.2.0（本轮实际环境）、配套 stdx、SQLite / JSON 兜底、Vue 3 + Vite + TypeScript、浏览器原生 WebSocket、Playwright、DeepSeek。

**Spec:** [2026-10-16-group-dining-agent-design.md](../specs/2026-10-16-group-dining-agent-design.md)。产品要求以该文件为准；原型仅作布局与交互参考。

**团队安排：** 两人协作，另一位成员负责部分后端，我负责前端及剩余后端。可直接交给对方的任务说明见[两人分工与后端交接](2026-10-17-two-person-backend-handoff.md)。本轮仅明确分工，具体执行方式之后再讨论；不重新要求选择代理执行模式。

## Global Constraints

- “先按成员计算适配关系，再选共享菜品”；“每位已填写成员至少有 2 道适合的非汤、非主食、非饮品菜”是目标，1 道提示不足，0 道不能确认完整方案。
- “辣度统一为‘不辣、微辣、中辣、重辣’”，内部 0–3；用户上限为空表示都可以。
- 过敏按已录入食材（含调料/汤底）基础过滤，AI 只补充关联；不建设过敏原资料状态、制作确认、严重程度或交叉接触流程。
- 2026-10-18确认：`ingredients`中`unknown`表示其余食材不详；无食材限制者可适配，有不吃/素食要求者不计覆盖；任一已提交成员有过敏要求时整桌排除unknown菜及相关固定套餐。已知冲突仍优先，AI及规则降级不得补齐或清除未知项；细节见spec第3节。
- 菜品业务字段严格采用 spec 第 5 节；套餐只有“套餐名字、图片、组分[]、价格”，组分固定为同店 `{dishId, quantity}`。
- “总价为‘套餐售价 × 套数 + 额外单点售价 × 份数’”；组分不重复收费，覆盖按不同实际菜品去重。
- “登录不是扫码、进入餐馆、建局、邀请、选菜或推荐的前置步骤”；默认设置只预填，明确提交才计入已填写人数。
- 建局默认 4 人；聚餐局短码 4~6 位字母数字；房间 24h TTL；至少 1 位提交后可推荐；未齐只保留方案。
- 发起人可修改人数/预算、确认/重开；成员只修改本人需求；补充记录由创建者修改/删除。
- “全量快照广播”；同局推荐和对话互斥；结果提交、确认均检查房间与菜单版本。
- “一次推荐含重试的总等待上限为 30 秒”；最多重试 1 次；规则降级时显示“已切换规则推荐”，对话禁用。
- 本轮只实施 spec 范围，不增加订单/支付、附近餐馆、地图、自选换菜套餐或跨局历史。
- 用户当前有未提交的 spec、截图和原型；不得清理、重置或混入实现提交。执行隔离工作区时，必须让该工作区读到当前已确认的 spec 与本计划，不能误用 Git 中的旧 spec。

## Review Focus

1. 同一操作重发或重连：不重复建局、入局、生成推荐；分别由 P2/T2、P2/T3 测试。
2. 用户从账号页返回、跨餐馆浏览：草稿不丢、不串店，身份不重复；由 P3/T1、P3/T2 测试。
3. 商家修改菜单发生在推荐中途或确认之后：旧方案不能提交或继续确认；由 P2/T3 测试。
4. 空输入、小数价格、重复套餐组分或无效数量：校验清楚、计价精确、覆盖不重复；由 P1/T2、P1/T4、P2/T1 测试。
5. 模型输出包含跨店菜、冲突食材、恶意文字或超时：不能越过规则或权限，仍能规则推荐；由 P4/T1、P4/T2 测试。

## 当前基线与实施顺序

- 已复核 `cjc / cjpm / cjfmt` 均为 **1.2.0**，目标 `x86_64-unknown-linux-gnu`；本机 Node **22.23.1**、npm **10.9.8**。
- SDK 路径：`/home/luorong/.local/opt/cangjie-1.2.0/cangjie`。非交互 shell 需显式加载 `envsetup.sh`；不要要求用户重复安装 SDK。
- spec 原写 SDK 默认 LTS 1.0.5；实施基线采用用户现有 1.2.0，暂不改动冻结的 spec。网络扩展库、SQLite 适配、实际编译运行仍未验证。
- Git 已跟踪的内容只有 spec，目录另有原型与截图；没有可复用的正式前后端代码。

| 顺序 | 计划 | 独立验收结果 |
| --- | --- | --- |
| P1 | [基础服务、账号与菜单](2026-10-17-platform-catalog-plan.md) | 仓颉 HTTP/WS 可运行；账号、菜单、套餐与持久化 API 可测试 |
| P2 | [多人协作与规则推荐](2026-10-17-room-rules-plan.md) | 两个独立客户端能进同一局、提交需求、规则推荐、确认和恢复 |
| P3 | [用户端与商家端界面](2026-10-17-web-app-plan.md) | 无模型密钥也能通过正式页面完成访客及登录流程 |
| P4 | [AI 接入与整体验收](2026-10-17-agent-release-plan.md) | AI 增强、对话、30 秒降级及完整演示可验证 |

表中顺序表示集成和验收依赖。先由我完成共享骨架与接口，再按下表并行；开发时的mock不作为阶段完成证据。P2 不等 AI；P3 以规则模式验收；P4 不能替代 P2 的规则和权限校验。每个任务先测预期失败，再实现、测通过；只在失败或新改动有必要时扩大测试。

## 两人任务归属

| 负责人 | 任务范围 | 对应原计划 |
| --- | --- | --- |
| 我这边 | 工具链/网络验证、共享模型/错误类型/Repository接口、服务装配 | P1/T1；P1/T2 的共享骨架部分 |
| 另一位成员 | Repository持久化实现、演示数据、餐馆/菜单查询、账号与默认设置、商家餐馆/菜品/套餐管理API | P1/T2 的数据服务部分；P1/T3、P1/T4 的模块实现及模块测试 |
| 我这边 | 食材字典、个人适配、套餐展开计价、规则推荐、房间身份/协作/权限、WS与版本失效 | P2 全部 |
| 我这边 | C端及商家端全部页面、扫码/二维码、账号导航与草稿 | P3 全部 |
| 我这边主责、对方修复所属模块问题 | AI、对话、降级、端到端联调与最终交接 | P4 全部；涉及演示菜单/账号/存储的修改由对方提交 |

具体文件归属、共享接口与交付批次以[后端交接文档](2026-10-17-two-person-backend-handoff.md)为准。P1原任务里列出的入口、构建配置与共同接口文档仍由我集成，对方不需要直接修改这些共享文件。

## 文件边界

| 路径 | 职责 |
| --- | --- |
| `cjpm.toml`、`cjpm.lock`、`src/main.cj` | 仓颉模块、依赖锁与程序入口 |
| `package.json`、`package-lock.json` | Node 集成测试的依赖与锁；`ws` 只用于测试客户端，不替换浏览器原生 WS 或仓颉服务 |
| `src/app/`、`src/platform/` | 路由装配、HTTP/WS、环境与配置适配 |
| `src/model/` | spec 模型、传输 DTO、错误类型；不调用网络 |
| `src/store/` | 同一 Repository 接口，SQLite 或原子 JSON 实现 |
| `src/auth/`、`src/catalog/`、`src/room/` | 账号、菜单与房间业务服务和各自 HTTP/WS 适配 |
| `src/agent/` | `rules.cj`、`llm.cj`、`tools.cj`、`prompt.cj`，以及任务协调与校验 |
| `frontend/src/`、`frontend/admin/index.html` | C 端与商家端源码、共享 API/类型和页面；Vite 多入口构建 |
| `web/`、`web/admin/` | 构建产物，仓颉托管；不直接手改，不覆盖 `docs/prototypes/` |
| `data/fixtures/`、`scripts/`、`tests/` | 演示菜单、启动/验收脚本、跨服务测试；运行数据与密钥不入 Git |

## 共同接口约定

这些是实施选择，不增加产品功能。P1/T2 的共享骨架由我在 `docs/dev/contracts.md` 和 `src/model/` 落成类型，后续任务按同名接口接入；对方提交接口变更建议，我同步消费者和测试。字段命名及对方API的返回约定见后端交接文档。

- 金额采用整数分 `Int64`：`priceFen`、`totalFen`、`budgetPerPersonFen`；前端显示元，禁止二进制浮点累加金额。数量为正整数，所有 id 为字符串。
- `Outcome<T>` 为业务结果 `Ok(T) / Err(DomainError)`；`DomainError` 包含 `code`、`message`。HTTP 错误 `{error:{code,message}}`，WS 错误另带 `requestId`。
- `Actor` 包含已认证的可空 `userId`、`merchantId` 与 `visitorId`；cookie 会话解析得到身份，不能接受请求体伪造身份。公开浏览可没有visitorId，建局/进局前必须取得服务端访客会话；房间服务不接受缺失visitorId的变更。
- `Preferences` 包含 `allergens[] / avoidFoods[] / dietMode / maxSpiceLevel / tastePreferences[] / wantedDishIds[] / wantedSetMealIds[] / note`；`dietMode` 为 `none / ovoLacto / plant`，辣度上限为 `null / 0 / 1 / 2 / 3`。文字首版沿用 200 字。
- `MenuSnapshot` 包含 `restaurant / menuVersion / dishes[] / setMeals[]`。每次菜单写入原子增加该店 `menuVersion`。
- `normalizeIngredients(values: Array<String>): Array<String>`由共享模型校验层提供：保留已知食材，归一化并去重`unknown`；空数组/全空白转为`["unknown"]`。持久化与菜单API不能过滤掉该标记，不新增商家录入的完整性状态字段。
- `MemberFit.status`为`fit / conflict / uncertain`，另有事实原因；明确冲突为conflict，有食材限制且未知为uncertain，只有fit计入该成员覆盖。它是推荐派生结果，不是商家菜品属性；推荐的fits仅列fit成员，uncertain原因及未知食材提示供页面展示。
- `RoomSnapshot` 包含 `session / stateVersion / menuVersion / members[] / self / recommendation / recommendationInvalid / job`；`self` 才包含本人的未提交草稿，其他成员只显示已提交要求及填写状态。
- `RuleInput` 包含菜单、已提交成员、声明人数、可选人均预算和 `IngredientAssociations`，可选 `baseItems / adjustment`；关联输入默认空，规则引擎不调用模型。首版规则快捷调整 `RuleAdjustment` 仅 `addSoup`，通过 `request_recommendation` 的可选payload传入，不冒用自由对话。
- `RecommendationDraft` 包含 `items[] / expandedDishes[] / fits[] / totalFen / undercoveredIds[] / uncoveredIds[] / unmetWishes[] / budgetWarning`；条目为 `{itemType: dish|setMeal,itemId,quantity}`。
- `Recommendation` 在草稿上增加 `id / sessionId / roomVersion / menuVersion / mode: rules|ai / canConfirm`。`canConfirm` 由服务端基于全员提交、覆盖和最新版本计算。
- HTTP：`GET /health`；`GET /api/restaurants/:restaurantCode`；`GET /api/restaurants/:restaurantCode/menu`；`POST /api/sessions` 输入 `{restaurantCode,people,budgetPerPersonFen,requestId}`；`GET /api/sessions/:roomCode` 读取本人的快照。匿名身份首次建局/进局时建立，公开看菜单不计房间成员；Node集成客户端用`ws`显式带各自cookie，浏览器沿用原生WS。
- 账号：`POST /api/user/register|login|logout`、`GET /api/user/me`、`GET|PUT /api/user/default-settings`；商家独立 `/api/merchant/register|login|logout`、`GET /api/merchant/me`；注册返回账号，登录建立会话。`POST /api/visitor/session`幂等确保访客cookie，不要求账号，也不创建房间成员；房间创建/连接前由我这边调用。访客 cookie 与两种账号 cookie 分离。
- 商家：`POST|GET|PUT /api/merchant/restaurant`；`POST /api/merchant/dishes`、`PUT|DELETE /api/merchant/dishes/:id`；套餐对应 `/api/merchant/set-meals`。商家菜单读取复用已归属校验后的目录服务。
- WS：`/ws`，请求 `{type,requestId,payload}`；事件名沿用 spec 第 6.3 节，变更操作带 `expectedVersion`；客户端不传有效 actor。`join_room` 通过 cookie 与 roomCode 恢复本人；请求重发用 `requestId` 去重。
- 路由：主页 `/`，餐馆 `/r/:restaurantCode`，房间 `/s/:roomCode`，个人要求/菜单/推荐为该房间的子路由，账号 `/account`，商家 `/admin/`。餐馆菜单 `/r/:restaurantCode/menu`。未知 API 返回 JSON 404，不回退成 SPA HTML。

## 验收与交接规则

所有计划目前均为**待执行**；工具版本验证不等于网络、存储或业务已验证。每个任务通过后只提交自己负责的新建/修改文件，不笼统 `git add .`。本次已确定人的分工，开发工作区、提交方式与具体执行方法之后讨论；当前不开始实现、不向另一位成员发送消息。

最终覆盖：P1 对应 spec 4/5/9，P2 对应 3/5/6/8 的规则与生命周期，P3 对应 1/6/7/9 的页面流程，P4 对应 8/10/11 的模型、降级和集成；13 的排除项贯穿所有阶段。先完成全部阶段才可称本版实现完成。

## 已核对的技术参考

- [仓颉 stdx HTTP/WS 官方说明](https://github.com/cangjielanguage/cangjie_stdx/blob/main/doc/libs_stdx_en/net/http/http_package_overview.md)：使用配套扩展库；具体 1.2.0 二进制与依赖以 P1 编译验证为准。
- [cjpm 1.2.0 手册](https://cj-docs.gitcode.com/zh/1.2.0/tools/source_zh_cn/cmd-tools/cjpm_manual.html)：测试文件跟随包；本机已核对 `cjpm test --filter`、`cjfmt -h`。
- [DeepSeek 工具调用文档](https://api-docs.deepseek.com/guides/function_calling)、[ZXing 浏览器库](https://github.com/zxing-js/browser)、[Vite 入门](https://vite.dev/guide/)：实施时锁定兼容版本，不假定原型已具备这些能力。
