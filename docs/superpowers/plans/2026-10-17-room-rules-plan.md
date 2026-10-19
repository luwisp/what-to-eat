# P2 多人协作与规则推荐 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 不依赖 AI，完成真实多人进局、提交需求、套餐规则推荐、确认和恢复。

**Architecture:** 纯规则函数计算适配与组合；RoomService 持久化房间状态、身份和权限；WS 转发命令并按连接发送完整快照。推荐协调器在锁内取得版本快照，锁外计算，提交时再次复检。

**Tech Stack:** P1 仓颉服务与 Repository、原生 WS、仓颉测试、Node 双客户端集成测试。

**Spec:** [设计文档](../specs/2026-10-16-group-dining-agent-design.md)；前置 [P1](2026-10-17-platform-catalog-plan.md)，接口见[总计划](2026-10-17-group-dining-implementation.md)。

**两人归属：** 全部由我负责。消费另一位成员交付的Repository/AuthService/CatalogService；目录提交后的菜单版本通知由我接入房间失效处理，不让对方在目录模块中导入房间服务。对方模块的问题交回所属模块修复，具体见[后端交接](2026-10-17-two-person-backend-handoff.md)。

## Global Constraints

- 继承总计划的全部约束与接口；先完成 P1。
- “普通忌口按个人匹配”，过敏命中采用整桌排除；未提交不等于无要求。
- “全量快照广播”；“同一局同时只允许一个推荐任务进行中”。
- `open / recommended / closed`；24h TTL；确认/重开和人数/预算修改仅发起人授权。
- unknown按spec第3节处理：无食材限制者可适配；有不吃/素食要求者记uncertain、不计覆盖；任一已提交成员有过敏要求时整桌排除unknown菜与包含它的固定套餐。已知冲突优先；AI和规则降级不得清除标记。

## Review Focus

1. 套餐荤素混合、重复组分、额外加份：逐菜适配，计价和覆盖去重，T1。
2. 汤/米饭/饮品不能掩盖0道合适菜，1道只警告，T1/T3。
3. 重复建局、重连、中途登录、补充同行人后本人扫码：不错误合并或重复计数，T2。
4. 两个客户端同时改版本或请求推荐，旧任务与旧确认无效，T3。
5. 数据重启、TTL到期、非创建人编辑补充记录：身份/权限不漂移，T2/T3。

### Task 1: 食材匹配、套餐展开、覆盖与确定性推荐

**Files:** Create `src/agent/rules.cj`、`src/agent/ingredients.cj`、`src/agent/rules_test.cj`、`data/fixtures/ingredients.json`。

**Interfaces:** Consumes P1 的 Preferences/MenuSnapshot/RecommendationDraft/RuleInput；Produces `evaluateMemberFit(dish: Dish,prefs: Preferences,associations: IngredientAssociations): MemberFit`、`expandItems(menu: MenuSnapshot,items: Array<RecommendationItem>): Outcome<ExpandedMenu>`、`validateRecommendation(input: RuleInput,items: Array<RecommendationItem>): Outcome<RecommendationDraft>`、`buildRuleRecommendation(input: RuleInput): Outcome<RecommendationDraft>`。`MemberFit` 为status（fit/conflict/uncertain）及事实原因，只有fit算覆盖；`ExpandedMenu` 为展开菜品、份数、totalFen，保留食材不完整提示。

`RulesTests`增加unknown矩阵：`["土豆","unknown"]`对无食材限制者fit、对不吃香菜/素食者uncertain；`["鸡肉","unknown"]`对素食者conflict而非uncertain；任一已提交过敏要求使unknown菜及相关套餐全桌排除，草稿过敏项尚未提交则不触发。仅辣度限制时仍按已填写辣度判断。无过敏的混合套餐中，2道完整适配素菜+1道unknown菜对素食者覆盖2，不把未知组分整包扩散为全部不适配；只有unknown可选时有食材限制者覆盖0、不能完整确认。新增/移除标记触发CoordinatorTests的菜单版本失效路径。

- [ ] **Step 1 — 写失败用例。** `RulesTests` 固定样例断言：蛋奶素成员只适配套餐中的素菜而非荤菜；一人不吃辣不排除其他人的辣菜；任一已提交者花生过敏则含花生油组分的套餐整套排除；鱼/虾蟹/贝类分开；调料、汤底计入。`@Expect(expanded.totalFen, 16000)`（套餐12800分+额外菜3200分）、`@Expect(coverageOfRepeatedDish, 1)`（同菜3份），只有汤/米饭覆盖0，0/1/2道对应不可确认/不足/达标目标。
- [ ] **Step 2 — 运行。** `bash scripts/cj.sh test --filter 'RulesTests.*'`，确认失败。
- [ ] **Step 3 — 实现纯函数。** 本地字典归一食材名称与类别，AI关联输入只能收缩适配范围；按组分可售性和同店归属过滤。组合先覆盖选择最少者，再补足2道目标、愿望和数量搭配；优先选能减少更多未覆盖/不足成员的条目，同效时比较预算差额、愿望满足、价格和稳定itemId。预算内可替代组合优先，超出必须返回金额提示；所有候选不覆盖某人时保留部分结果，不能编造菜或放宽限制。额外加份不自动由重复愿望产生。
- [ ] **Step 4 — 验证。** 上述测试及同输入多次完全相同、全员无菜、仅套餐可覆盖、AI试图恢复明确冲突、未提交成员不参与约束/覆盖、输入愿望冲突被排除并返回原因等用例通过；addSoup在baseItems上增加一份可售且至少适合一人的汤，无候选时保留原组合并说明。覆盖不足不是传输错误，合法部分组合仍返回 Ok 与缺口。
- [ ] **Step 5 — 保存检查点。** `git diff --check`；提交本任务文件，说明 `feat: add member coverage and deterministic meal rules`。

### Task 2: 房间身份、草稿提交、权限和持久化

**Files:** Create `src/room/service.cj`、`src/room/commands.cj`、`src/room/http.cj`、`src/room/room_test.cj`；Modify `src/app/server.cj`、`docs/dev/contracts.md`。

**Interfaces:** Consumes P1 Repository/AuthService、P2/T1适配；Produces `RoomService.create(actor: Actor,input: CreateSessionInput,requestId: String): Outcome<RoomSnapshot>`、`join(actor,roomCode: String): Outcome<RoomSnapshot>`、`snapshot(actor,roomCode): Outcome<RoomSnapshot>`、`apply(actor,roomCode,command: RoomCommand,expectedVersion: Int64,requestId: String): Outcome<RoomSnapshot>`。RoomCommand 对应更新需求、增改删同行人、改人数预算、确认、重开；推荐/对话由 T3 协调后调用服务提交。

- [ ] **Step 1 — 写失败用例。** `RoomTests`：`@Expect(created.session.people, 4)`、`@Expect(created.self.submitted, false)`、`@Expect(rejoined.self.id, original.self.id)`；第二人先提交可推荐；空选项submit=false不算提交、submit=true算无特殊要求；中途登录不新增/覆盖；同requestId建局返回同一房间；发起人/本人/补充记录创建人权限严格生效；24h后拒绝变更。
- [ ] **Step 2 — 运行。** `bash scripts/cj.sh test --filter 'RoomTests.*'`，确认失败。
- [ ] **Step 3 — 实现业务服务与创建/读取HTTP。** HTTP建局/连接准备层调用对方的ensureVisitor并处理cookie，WS从已有cookie解析Actor；服务端不能只依赖前端先初始化身份。visitorId与房间的身份映射持久化，登录只关联已有成员。新成员表单读取账号默认值但submitted=false；已有表单不被默认值覆盖；同行人不继承代填者默认值。提交与草稿分开保存，只有有效需求提交/删除及其他推荐条件变化才使推荐失效。实际成员超过声明人数时服务端将声明人数抬至实际人数下限并提示发起人核对；不允许手动调低到该下限以下。TTL使用可注入时钟，短码碰撞在事务中重新生成。
- [ ] **Step 4 — 验证。** 上述测试通过，加测重启后恢复同成员、旧expectedVersion拒绝并返回最新快照、其他成员看不到未提交草稿、本人扫码不自动认领补充记录、删除补充记录后重新填写、不足人数未齐不能完整确认。设置提交后的修改在同一事务撤销旧结果有效性。
- [ ] **Step 5 — 保存检查点。** `git diff --check`；提交本任务文件，说明 `feat: add persistent dining rooms and member identity`。

### Task 3: WS广播、单飞推荐、菜单变更失效与确认

**Files:** Create `src/room/websocket.cj`、`src/room/broadcast.cj`、`src/agent/coordinator.cj`、`src/agent/coordinator_test.cj`、`tests/room-integration.mjs`；Modify `src/room/service.cj`、`src/app/server.cj`、`src/catalog/service.cj`、`docs/dev/contracts.md`。

**Interfaces:** Consumes RoomService、CatalogService、规则函数；Produces `RecommendationCoordinator.request(actor,roomCode: String,requestId: String,adjustment: Option<RuleAdjustment>): Outcome<JobStatus>`、`commitResult(job: RecommendationJob,draft: RecommendationDraft,mode: RecommendationMode): Outcome<RoomSnapshot>`、`invalidateRestaurantRooms(restaurantId: String,menuVersion: Int64): Unit`。RecommendationJob含jobId、roomVersion、menuVersion、开始时间；JobStatus为started/inProgress。广播发送按actor构建的完整RoomSnapshot。

- [ ] **Step 1 — 写失败用例。** `CoordinatorTests`：`@Expect(startedJobCount, 1)`（并发请求及重发）、`@Expect(staleResultCommitted, false)`；计算中改需求/菜单，旧结果不提交；定格后改菜单撤销确认；非发起人确认/重开拒绝；未齐/0道/旧版本均拒绝确认，1道警告可确认；任务异常后锁释放。`room-integration.mjs` 用两个独立cookie客户端断言成员先填、完整快照同步、断线恢复不重复入局。
- [ ] **Step 2 — 运行。** `bash scripts/cj.sh test --filter 'CoordinatorTests.*'` 和启动服务后的 `node tests/room-integration.mjs`；预期未实现的WS/协调逻辑失败。
- [ ] **Step 3 — 实现协议和版本提交。** 帧按总计划解析，命令交业务服务，校验连接Origin与身份；广播不包含别人的草稿/凭证。短锁持久化条件变更并取得推荐输入，规则计算后在锁内对房间/菜单版本重新校验；确认同样复检。菜单更新主动使同店房间结果失效，即使房间closed也撤销旧确认；只有host重开后可编辑已定格需求。保留方案复用当前推荐持久化，不伪造完整确认。
- [ ] **Step 4 — 验证。** 单测、双客户端脚本通过；重启后恢复房间和结果，并将中断的inProgress作业标为终止、释放单飞状态，允许重新请求；断线重连取全量而非重放本地旧状态；未齐时界面所需计数/提示与canConfirm准确。断线或旧命令报错不终止其他连接。
- [ ] **Step 5 — 保存检查点。** `git diff --check`；提交本任务文件，说明 `feat: add collaborative rule recommendations and version checks`。

**阶段出口：** 不配置模型密钥，两个独立客户端可完成建局→邀请→分别提交→规则推荐→全员有菜且填写齐后确认→同房间重开。P1/P2测试和真实WS集成均通过，才能进入正式页面联调。
