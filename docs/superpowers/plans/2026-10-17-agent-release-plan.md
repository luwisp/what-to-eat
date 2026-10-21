# P4 AI 接入与整体验收 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为已可用的规则产品加入AI食材关联、文字整理、推荐和对话，并验证失效/降级与实际演示。

**Architecture:** 可替换的LLM适配器只处理外部协议，工具层限制同店操作；协调器复用P2的锁与版本提交。模型生成的菜单是候选，规则复检后的结果才广播；规则推荐始终可独立运行。

**Tech Stack:** 仓颉HTTP/JSON、DeepSeek工具调用、mock适配器与可注入时钟、Playwright。

**Spec:** [设计文档](../specs/2026-10-16-group-dining-agent-design.md)；依赖P1–P3，接口见[总计划](2026-10-17-group-dining-implementation.md)。

**两人归属：** AI和集成主责由我承担；T3若需修改`data/fixtures/restaurants.json`或修复账号/目录/持久化模块，由另一位成员提交，我复跑端到端验收。双方不同时修改对方负责的实现文件，见[后端交接](2026-10-17-two-person-backend-handoff.md)。

## Global Constraints

- 继承总计划全部约束与P2版本/权限校验；不重新实现一套AI专用确认流程。
- “一次推荐含重试的总等待上限为 30 秒”；“失败最多重试 1 次，再失败走规则推荐”。
- AI不得改写配方、套餐、价格或明确冲突；自由文字不能静默删除既有硬限制。
- unknown代表未知剩余食材，AI不得按菜名/常见做法补全、删除标记或把uncertain改为fit；有过敏要求时的整桌排除同样适用AI与规则降级。
- 规则降级显示“已切换规则推荐”，自由对话禁用；后端不可访问时显示断线，不宣称离线推荐。

## Review Focus

1. 模型提供跨店/不存在id、浮点数量、篡改套餐或价格：校验拒绝，T1。
2. 用户补充含“忽略此前限制”等指令：只作为饮食数据，不改变权限或工具白名单，T1/T2。
3. 模型超时、无密钥、认证错误、连续坏JSON：在统一期限内降级，无无限重试，T2。
4. AI进行中被改需求/菜单、用户重发对话：旧输出不可提交、同局仍单飞，T2。
5. Mock扫码/模拟成员被误当真实设备验证：分开记录浏览器、手机、真实API证据，T3。

### Task 1: LLM适配、工具边界与文字建议

**Files:** Create `src/agent/llm.cj`、`src/agent/tools.cj`、`src/agent/prompt.cj`、`src/agent/llm_test.cj`、`src/agent/tools_test.cj`、`src/agent/interpretation.cj`、`src/agent/http.cj`；Modify `src/app/server.cj`、`docs/dev/contracts.md`。

**Interfaces:** Consumes P1 CatalogService/Deadline、P2规则；Produces `LLMClient.complete(messages: Array<ModelMessage>,tools: Array<ToolDefinition>,deadline: Deadline): Outcome<ModelReply>`、`ToolRegistry.execute(context: ToolContext,call: ToolCall): Outcome<ToolResult>`、`interpretPreferences(prefs: Preferences,note: String,deadline: Deadline): Outcome<PreferenceSuggestions>`、`inferAssociations(menu: MenuSnapshot,prefs: Array<Preferences>,deadline: Deadline): Outcome<IngredientAssociations>`。ToolContext含当前餐馆、房间与actor；ToolResult只能是查菜事实或待校验的组合提案。`POST /api/preferences/interpret`返回结构化建议及原文，不直接写房间/默认设置。

`ToolTests`包含模型声称“这道菜通常全素，所以unknown没有肉”“unknown肯定不含花生”的反例：不修改商家食材，uncertain不变；过敏局仍排除相关菜/套餐。提示词明确unknown不是待模型补齐的占位配方；目录工具返回已知食材和unknown原标记。

- [ ] **Step 1 — 写失败用例。** `LLMTests` mock覆盖请求/响应、工具调用id关联、坏JSON、请求超时取消、后端密钥不进入前端；`ToolTests`断言同店查询、跨店id拒绝、条目数量非正整数拒绝，`@Expect(validated.totalFen, serverTotalFen)`（模型谎报价格），模型提供配方不能覆盖服务端事实；“忽略过敏限制”不能产生修改权限/默认设置的工具调用。
- [ ] **Step 2 — 运行。** `bash scripts/cj.sh test --filter 'LLMTests.*,ToolTests.*'`，确认失败。
- [ ] **Step 3 — 实现。** 适配层使用后端环境变量`DEEPSEEK_API_KEY / DEEPSEEK_BASE_URL / DEEPSEEK_MODEL`，模型名由配置提供，不把易变名称写死在业务。工具白名单为搜同店菜/查菜及套餐/提出组合调整，不允许执行任意URL或更新硬限制；上下文由服务端注入。文字建议只增补待确认标签，不能自动清空结构化限制；关联只引用商家已有食材，不补写未知配方。
- [ ] **Step 4 — 验证。** 上述测试通过，加测已知冲突不会被AI关联“纠正”为适合、套餐部分适配、原文无法理解时原样保留并提示；所有工具返回仍需P2 validateRecommendation。用mock完成此任务，不以真实API成功替代边界测试。
- [ ] **Step 5 — 保存检查点。** `git diff --check`；提交本任务文件，说明 `feat: add bounded model adapter and dining tools`。

### Task 2: AI推荐、对话、确认建议与30秒降级

**Files:** Create `src/agent/assistant.cj`、`src/agent/assistant_test.cj`、`frontend/src/features/recommendation/ChatPanel.vue`、`frontend/e2e/agent.spec.ts`；Modify `src/agent/coordinator.cj`、`src/room/websocket.cj`、`frontend/src/features/preferences/PreferencesPage.vue`、`frontend/src/features/recommendation/RecommendationPage.vue`、`docs/dev/contracts.md`。

**Interfaces:** Consumes P4/T1与P2协调器；Produces `DiningAssistant.recommend(input: RuleInput,deadline: Deadline): Outcome<AssistantResult>`、`adjust(input: RuleInput,current: Recommendation,text: String,history: Array<ChatMessage>,deadline: Deadline): Outcome<AssistantResult>`。AssistantResult含校验后草稿、mode、事实解释、可选降级原因；coordinator增加`chat(actor,roomCode,text,requestId): Outcome<JobStatus>`，仍用同局互斥与commitResult。配置无有效模型时直接规则模式。

`AssistantTests`及`agent.spec.ts`验证unknown规则在首次推荐、对话和超时降级中一致，不能靠解释文本补覆盖；只剩未知菜导致0覆盖时保留部分结果/信息不足提示，不新增餐厅审核状态，也不能启用完整方案确认。

- [ ] **Step 1 — 写失败用例。** `AssistantTests`用假时钟断言`@Expect(elapsedMillis <= 30000, true)`、`@Expect(retryCount <= 1, true)`；整次关联/工具/生成/重试共享期限；认证错误直接规则、超时或第二次坏JSON规则；AI中途菜单/需求变化不能提交；并发chat与recommend只1任务，重发去重。`agent.spec.ts`断言自由文字识别标签须保存后提交、不能删除原限制、对话调整价格与套餐按事实复检。
- [ ] **Step 2 — 运行。** `bash scripts/cj.sh test --filter 'AssistantTests.*,CoordinatorTests.*'`、frontend目录 `npm run test:e2e -- agent.spec.ts`，确认失败。
- [ ] **Step 3 — 实现统一编排。** 一次作业以单调时钟设置30秒deadline，所有HTTP/工具阶段消耗同一预算；最多3轮模型请求（含最多1次失败重试），轮数或剩余时间不足直接规则兜底，迟到输出丢弃。优先规则算明确匹配，AI补充关联后再组合；返回前执行P2校验。对话不能静默改成员硬限制，若请求冲突则解释并提示本人改表单；chat_delta仅作进度/对话，菜单结果经复检才显示。聊天历史轻量落库。文字识别建议在表单展示，保存时一并确认；无法识别不阻止手动保存。
- [ ] **Step 4 — 验证。** 相关测试通过；规则模式显示“已切换规则推荐”及禁用自由对话，仍可规则推荐和addSoup快捷操作；后端断线显示重连；全员无菜不编造推荐；超预算显示实额；stale job不污染最新快照。完整跑P2规则测试，确保不依赖模型。
- [ ] **Step 5 — 保存检查点。** `git diff --check`；提交本任务文件，说明 `feat: add validated AI dining and timed rule fallback`。

### Task 3: 整体验收、演示数据与运行交接

**Files:** Create `README.md`、`.env.example`、`scripts/dev.sh`、`scripts/check.sh`、`scripts/llm-smoke.mjs`、`docs/dev/acceptance.md`；Modify `frontend/playwright.config.ts`、`data/fixtures/restaurants.json`、`docs/dev/environment.md`。

**Interfaces:** Consumes全部已实现能力；Produces `bash scripts/dev.sh`启动说明、`bash scripts/check.sh`统一非真实付费API检查、`node scripts/llm-smoke.mjs`显式真实API验收入口。验收使用独立临时数据目录，不写用户演示数据库；脚本接收`JUXIAOBAO_DATA_DIR / JUXIAOBAO_PORT / JUXIAOBAO_PUBLIC_BASE_URL`。

- [ ] **Step 1 — 写剩余验收用例。** 将spec第11节逐条映射至现有测试，缺项补到归属测试文件：真实两context并发、访客/登录混用、套餐售价/去重、0/1/2覆盖、成员未齐、菜单改动/下架、同房间重开、重启、相机拒绝和无效码；不得仅添加复述实现的断言。
- [ ] **Step 2 — 运行新增用例。** 仅对缺项先跑对应测试，确认因缺失行为失败；若未发现缺项，记录覆盖映射，不人为制造红灯。
- [ ] **Step 3 — 补齐运行交接。** 文档写明SDK/stdx/存储选择、首次初始化、开发/构建/生产启动、公共可访问链接配置、HTTPS或可信开发环境的相机验证条件、两种账号登录与重置方式、无模型降级、数据目录与停止方法；.env.example不含真实凭证。只修验收实际暴露的问题，按所属任务范围提交。
- [ ] **Step 4 — 运行最终验证并留证。** `bash scripts/check.sh`依次运行仓颉测试、真实HTTP/WS集成、frontend typecheck/Vitest/build/Playwright；真实模型冒烟显式配置密钥后另跑10次，每次记录实际模式/时长/校验结果，规则兜底不得计为AI成功。使用手机浏览器至少完成餐馆扫码、邀请第二设备进局、默认设置返回与推荐展示；设备或凭证缺失就标记未验证及复现步骤，不伪报通过。
- [ ] **Step 5 — 交付与保存检查点。** `git diff --check`；提交归属文件，说明 `docs: add verified dining app runbook and acceptance`；报告真实通过项、仍未验证项和操作入口，不自行部署或发布。

**完成标准：** spec范围全部对应实现与验收；运行交接可复现；无模型也能规则闭环；真实API及手机项目只有取得实际证据后才能勾选。未验证的外部能力不因前端可点击而标记已完成。
