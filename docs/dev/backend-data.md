# B2 账号、会话和默认设置交接

基线提交：`1fe4ad8`，交付日期：2026-10-19。

本批只实现 `src/auth/`，消费既有 `Repository`、模型、平台密码绑定与 HTTP Router。B1 持久化、B3 目录、共享模型和主程序装配由对应负责人维护。

## 装配

```cangjie
import huaiwei.auth.*
let auth = AuthService(repository, publicOrigin: publicOrigin)
let defaults = DefaultSettingsService(repository)
// auth 实现 IdentityResolver，可直接传给 createDiningServer。
// 在 createDiningServer 的 registerBackend 回调内：
registerAuthRoutes(router, auth, defaults)
```

所有服务必须注入同一个真实 Repository；不要为认证创建第二个数据库。`publicOrigin` 为浏览器访问的完整 origin（协议、主机和可选端口，无末尾斜杠），默认 `http://localhost:8080`，部署时显式传入。HTTPS 自动设置 Secure。启动时及后台定期调用 `auth.pruneExpired()`；登录、退出和 ensureVisitor 也会清理过期记录，身份解析始终拒绝过期记录。

`logout(kind, cookies: String)` 接收原始请求 Cookie 头，撤销当前浏览器的对应会话。计划中的 `logout(kind, actor)` 没有会话标识，无法区分同一账号的多个浏览器，因此没有采用；HTTP 路由不变。

## 行为与字段

- 用户和商家各自注册、登录、退出、me；同一 login 可分别存在于两种账号中，各类型内唯一。注册 201，不自动登录；登录 200；退出幂等 204。
- login 为 1–128 UTF-8 字节、不含 ASCII 空白/控制字符，大小写敏感；密码为 8–1024 UTF-8 字节，保留原文空白。只接受 `{login,password}`。
- 密码格式 `pbkdf2-sha256`，OpenSSL PBKDF2-HMAC-SHA256，600000 次、随机 16 字节盐、32 字节散列，十六进制保存。验证固定长度散列时逐字节累计异或，不提前退出。B1 演示账号可调用 `hashPassword`，禁止保存明文。
- cookie 为 `hw_user`、`hw_merchant`、`hw_visitor`，均为 Path=/、HttpOnly、SameSite=Lax；HTTPS 添加 Secure。账号 7 天，访客 30 天。token 来自安全随机 32 字节，只在 Set-Cookie 中返回；库中保存 SHA256 摘要。登录会轮换当前浏览器的同类型旧会话，其他浏览器及其他类型会话保留。
- `resolve` 同时解析三种身份；`ensureVisitor` 恢复已有访客或新建访客，不创建房间/Participant。账号登录、退出不改变仍有效的 visitorId。
- 默认设置只允许 `allergens,avoidFoods,dietMode,maxSpiceLevel,tastePreferences`；PUT 为完整替换，全部五个字段必填。dietMode 为 none/ovoLacto/plant，辣度 null 或 0–3；数组最多 100 项，每项 1–256 字节且不能全空白。
- HTTP 拒绝 userId、updatedAt、note、wantedDishIds、wantedSetMealIds、预算及人数等额外字段。内部 put 始终以可信 Actor 的 userId 覆盖输入 userId；商家/访客无权访问。响应包含会话所属 userId 和 updatedAt。首次 GET 返回空数组、none、null，updatedAt=0。
- 变更请求有 Origin 时要求匹配配置；无 Origin 时拒绝 Sec-Fetch-Site: cross-site，允许命令行客户端。错误统一 `{error:{code,message}}`，不回显凭证或异常内容。

## API 与错误

`POST /api/visitor/session`；`POST /api/{user,merchant}/{register,login,logout}`；`GET /api/{user,merchant}/me`；`GET/PUT /api/user/default-settings`。

| 错误码 | 状态 | 场景 |
| --- | --- | --- |
| INVALID_INPUT | 400 | 非法 JSON、字段、账号/密码或默认设置 |
| INVALID_CREDENTIALS | 401 | 账号不存在或密码错误，统一提示 |
| UNAUTHENTICATED | 401 | 未登录、会话过期/失效或商家访问用户设置 |
| INVALID_ORIGIN | 403 | 跨站变更请求 |
| ACCOUNT_EXISTS | 409 | 同种账号的 login 重复 |
| INTERNAL_ERROR | 500 | 未预期的内部异常，隐藏异常详情 |

Repository 返回的错误保留其 code/status/message；持久化实现应返回不含敏感数据的错误。密码散列、会话和默认值都写入共享 DatabaseSnapshot，事务失败不返回成功或有效新 cookie。

## 验证与边界

```sh
export HUAIWEI_CANGJIE_SDK=/你的SDK路径/cangjie
bash scripts/cj.sh test --filter 'AuthTests.*,DefaultsTests.*'
```

本机临时 SDK 路径 `/tmp/huaiwei-sdk/cangjie`，官方 1.2.0 下载包 SHA256 为 `8c5fd944cd9cc51ee63d4a240e3ecc4f540345dae1468e8b47c927ecf2ba998f`。本机内存不足 1 GB，测试命令需额外设置 `cjHeapSize=64MB` 并使用 `-j 1`；官方说明见 [runtime 环境变量](https://cj-docs.gitcode.com/zh/1.2.0/dev-guide/source_zh_cn/Appendix/runtime_env.html)。根依赖配置未变；`.deps/build-tools/bin` 中仅放了本机 clang-15 的忽略链接。

AuthTests 使用带写锁、深拷贝、故障注入的测试 Repository；HTTP 用例启动真实仓颉 HTTP 服务并调用真实认证模块。公开菜单路由为只读 fixture，因为 B1/CatalogReader 尚未交付。重新构造 AuthService 验证从共享快照恢复，不等价于 SQLite 进程重启验收。真实落盘、重启、真实菜单和主程序挂载需要 B1 及总装负责人联调。

### 本批执行结果

2026-10-19，在本机 Cangjie 1.2.0 / OpenSSL 3.0.2 下执行：

```sh
HUAIWEI_CANGJIE_SDK=/tmp/huaiwei-sdk/cangjie cjHeapSize=64MB \
  bash scripts/cj.sh test -j 1
```

退出码 0，44/44 通过，0 skipped/error/failed；包含新增 AuthTests 4 项、DefaultsTests 2 项，以及原有 38 项。B2 源码已经 cjfmt 格式化并通过空白检查。单独定向命令仍可使用前文的 filter。测试运行器和 HTTP 用例需要本地 socket 权限。

真实 HTTP 用例调用记录（不记录密码、token 或 Set-Cookie 内容）：

| 步骤 | 结果 |
| --- | --- |
| POST /api/visitor/session | 204 |
| POST /api/user/register | 201，响应无密码字段，未自动登录 |
| POST /api/user/login | 200，响应无 token 字段 |
| PUT /api/user/default-settings | 200 |
| GET /api/user/default-settings | 200，保存的花生过敏设置可读回 |
| PUT 默认设置并传 userId | 400 |
| POST /api/user/logout | 204 |
| GET /api/user/default-settings（旧 cookie） | 401 |
| GET /api/restaurants/TEST/menu（公开 fixture） | 200 |
| 商家 register/login/me | 201/200/200 |
| 商家 cookie 读取用户默认设置 | 401 |
| 商家 logout 后 me | 204 后 401 |
| 跨源 Origin 发起登录 | 403 |

单元测试另验证随机盐、错误密码、同类型账号冲突、会话轮换/过期/清理、独立身份恢复、写入失败保留旧状态、默认值授权与非法字段拒绝。尚待联调：由总装负责人使用同一真实 Repository 挂载 registerAuthRoutes，并联合 B1 验证 SQLite 落盘/进程重启恢复和真实公开菜单。本批没有修改主程序或将测试仓库用于生产。
