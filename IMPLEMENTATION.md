# 本侧实现与联调

当前分支 `main`，在原目录实现；`docs/` 继续按用户设置忽略。本文件只说明实现代码和联调，不取代本机 spec/plan。已有 README 的个人修改保留。

## 准备与运行

```sh
export HUAIWEI_CANGJIE_SDK=/你的SDK目录/cangjie
bash scripts/bootstrap-deps.sh --local-tools   # 已有适配Clang15/OpenSSL可省略参数
npm ci
npm --prefix frontend ci
frontend/node_modules/.bin/playwright install chromium
bash scripts/check.sh
```

`bash scripts/dev.sh` 构建并启动前端静态托管/平台；真实业务入口还需队友提供 Repository、IdentityResolver、账号和菜单路由，再从 `src/main.cj` 调用装配入口。`Ctrl+C` 停止。

需要先看本侧组件交互时显式运行：

```sh
bash scripts/dev.sh --component-demo
# 浏览器打开 http://127.0.0.1:8080，输入餐馆码 TEST
```

这是组件联调：使用真实仓颉房间/WS/规则服务，但数据和访客适配器仅存在于 `tests/support/dining-server.cj`，启动时清空、退出不持久化，模型强制关闭。不能把它当账号、商家写入或持久化已交付。账号/商家页面通过独立前端API契约测试，待对方真实模块联调。

## 已实现的本侧代码

- `src/agent/`：本地食材字典、按人适配、unknown规则、固定套餐展开/计价、0/1/2道覆盖、预算软目标与确定性推荐，按声明人数估算份数。`data/fixtures/ingredients.json` 是本地类别字典的源，`scripts/generate-ingredients.py`生成编译代码；未知配方不会被字典或模型补齐。
- `src/room/`：稳定访客映射、建局/邀请先于填写、默认值只预填、私有草稿与提交分离、补充同行人权限、人数下限、幂等、TTL拒绝及清理、按actor生成快照、真实WS和断线恢复、单飞、版本失效、确认/重开、中断任务恢复。
- `src/agent/llm.cj`：只在后端读取模型配置，HTTPS/SNI/证书校验、受截止期限约束的HTTP、关闭超时socket、最多一次失败重试。工具只查同店事实和提出待校验组合；结果重新计算价格/覆盖。认证失败直接降级，无密钥或未配置模型名时纯规则运行。
- `src/agent/interpretation.cj`：文字建议不删除或放宽既有结构化要求，不直接提交房间或保存账号。AI关联仅能增加已有食材的排除关系，结果提交保留关联证据，不能恢复被收缩的适配。
- `frontend/`：Vue用户端/商家端多入口。主页扫码或输码、店内菜单与套餐、餐馆/成员隔离草稿、愿望、邀请二维码、个人输入/文字/同行人、推荐和聊天、可选账号默认设置、商家精确字段/unknown/套餐/入口二维码表单。原型目录未改。
- `src/platform/static.cj`：构建产物与两端深链托管；API未知路径保持JSON404，不回退HTML。

## 队友接入点

`createDiningServer(config, repository, identities, publicOrigin, registerBackend)`位于`src/app/server.cj`。它创建房间/协调器/传输层，恢复中断作业并安装前端托管。`registerBackend(router,onMenuCommitted)`回调由真实账号、菜单模块注册路由。目录提交并释放锁后调用`onMenuCommitted(restaurantId,menuVersion)`；不能在持久化事务中广播。测试入口同样使用此装配函数，未维护第二套路由服务。

`publicOrigin`必须与浏览器入口完全一致，如`https://dining.example`，不能带末尾斜杠。WebSocket校验Origin和服务端cookie身份；普通变更HTTP校验Origin/跨站来源。房间创建/WS准备层在服务端调用ensureVisitor，公开菜单不创建房间成员。

共享schema由`scripts/generate-models.py`生成仓颉实体与TS接口。后续增加的技术字段：`Session.menuVersion`用于去重失效通知；`RoomSnapshot.restaurantCode/messages`供菜单跳转和已提交聊天展示；`RecommendationJob.adjustment/text`支持作业恢复；`RecommendationDraft.associations`保留本次AI补充的收缩证据。`Recommendation.draft`是实际传输形状。解码完整存储记录需要全部键，不是公共请求解析器；原型数据不是可直接迁移的数据库。

推荐任务与菜单通知后都重新按实际版本复检；即使通知失败，读取快照也不能把旧菜单推荐显示为可确认。closed方案变更后撤销采纳，仍由发起人重开。草稿不会提升已填写人数或使旧推荐失效。

## 配置

复制`.env.example`自行配置。`scripts/dev.sh`在子shell读取`.env`，不打印密钥；运行数据与`.env`均忽略。模型名来自`DEEPSEEK_MODEL`，不假定服务商当前默认模型；`DEEPSEEK_BASE_URL`为API前缀，客户端补`/chat/completions`，仅允许HTTPS或回环HTTP测试地址。真实付费模型需单独显式冒烟，不包含在`check.sh`内。

## 验证边界

`check.sh`运行仓颉测试、真实HTTP/WS组件测试、Vitest、类型检查、生产构建和Playwright。`tests/support`中的内存仓库不证明实际SQLite事务/重启恢复，账号/商家网络拦截测试不证明对方API已实现。

真实手机摄像头、第二台实体设备扫码、真实模型API和队友真实持久化/账号/目录尚须联调验证。设备/凭证未提供时保留为未验证，不以mock冒充。当前相机失败的手动入口、两个独立浏览器context、窄屏与WS断开恢复有自动验证。

## 2026-10-18 自动验收结果

`bash scripts/check.sh`已完整运行并返回0：

| 检查 | 结果 | 能证明的范围 |
| --- | --- | --- |
| 仓颉测试 | 38/38，通过且无跳过 | 规则、unknown、套餐、房间/权限/幂等/版本、真实慢HTTP取消、模型工具/建议边界 |
| Node HTTP/WS | 6/6 | 平台4例；本侧真实服务的双客户端闭环及仓颉SPA/资源/API404/路径拒绝2例 |
| Vitest | 8/8 | 入口分流、草稿隔离、默认值字段、整数分、Vue代理复制、断线不重放与旧连接隔离 |
| TypeScript/生产构建 | 通过 | 两端正式源码可构建 |
| Playwright | 5/5 | 两个独立浏览器的点菜闭环/刷新、320px、相机失败回退、账号及商家API契约 |

最后一项账号/商家测试通过网络拦截验证前端，不替代对方后端验收。没有进行真实付费模型调用、真实设备相机或真实持久化重启验收。首次装配B1时请使用更新后的生成模型；新增技术字段尚未存在于先前G0输出中。

菜单改动后的失效通知仍由队友在提交成功、锁释放后调用。接入位置见上文；本侧没有修改`src/auth/`、`src/catalog/`、实际Repository或餐馆演示菜单。现有README/spec修改均未纳入本次实现提交。
