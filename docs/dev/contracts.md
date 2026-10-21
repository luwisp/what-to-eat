# G0 共用实现约定

## 归属及现状

当前目录 `main` 分支。G0为仓颉平台、共享模型/校验和Repository接口；持久化、认证、目录的实际实现继续由另一位成员负责。此文在忽略的docs目录，本地可读；代码中的接口和README随实现提交。

## 工程入口与路由

- `src/main.cj` → `src/app/server.cj`。Cangjie的main是关键字，不能作为子包；原计划的`src/main/server.cj`对应实际`src/app/server.cj`。
- 模块导入`juxiaobao.platform.*`、`juxiaobao.model.*`、`juxiaobao.store.*`。
- `HttpRouter.on(method, path, handler)`：method采用大写，path支持整段`:id`参数；handler为`(HttpContext, HashMap<String,String>) -> Unit`，在服务启动前注册。路径参数不含query，短码/id采用不含斜杠的字母数字/短横线。不要将用户输入直接拼进路径规则。
- `jsonResponse(ctx,status,value:JsonValue)`与`jsonError(ctx,status,code,message)`统一编码JSON。未知API404，匹配路径但方法错误405。`register(path, HttpRequestHandler)`保留给基础WS升级等平台路由。
- `registerAuthRoutes(router,auth,defaults)`及`registerCatalogRoutes(router,catalog)`由对方模块导出，由我在入口挂载。各服务构造时注入同一个Repository；目录模块实现`CatalogReader`，账号模块实现`IdentityResolver`。
- 路由处理请求体后逐个允许字段解析/校验；实体`fromJson`是完整持久化记录解码器，不当作公开输入解析器。不允许请求体传入userId/ownerId/visitorId来授权。

## 模型与JSON

`src/model/entities.cj`由`scripts/generate-models.py`内的单一schema生成；改变字段须修改schema并重新生成。默认构造函数均为命名参数。字符串枚举传输值沿用spec：`cold/hot/soup/staple/drink`、`none/ovoLacto/plant`、`open/recommended/closed`、`fit/conflict/uncertain`。金额Int64分，时间Int64 Unix毫秒。

完整记录有`toJson()`及`Type.fromJson(JsonObject)`，后者严格要求全部键与正确类型，可空值显式null；损坏/不支持的schemaVersion抛错，存储启动必须报错，不能回退空库。`DatabaseSnapshot()`是显式初始化空库，不能用来吞解析异常。构造器默认值方便业务建对象，不意味着外部输入合法。

`DatabaseSnapshot`包含`users/merchants/authSessions/visitorSessions/defaultSettings/restaurants/menuVersions/dishes/setMeals/sessions/participants/recommendations/chatMessages/dedupeRecords/jobs`，所有模块共用。`schemaVersion=1`。`MenuSnapshot`的菜品包含不可售条目，业务推荐层过滤。

`normalizeIngredients`保留已知食材及unknown、去首尾ASCII空白、归一unknown大小写并去重；空值归一`["unknown"]`。菜单保存必须调用它，不能凭模型补全。`parsePriceFen`用于元字符串转分；HTTP整数分输入仍须拒绝负数。`validateDishInput/validateSetMealInput`检查基础字段，跨店归属/套餐引用/重复组分合并由目录服务在事务内做。

`Participant.preferences`为最近提交的有效要求；`draft`为个人草稿，`submitted=false`不参与推荐。`visitorId`用于后端身份恢复，`userId`可空。公开成员使用`ParticipantView`，绝不直接广播完整Participant；只有`RoomSnapshot.self`可携带本人草稿。`Recommendation`使用`draft`字段容纳完整`RecommendationDraft`，另带版本/模式/确认状态；这是实际JSON形状，前端跟随它，避免重复两套字段。

## Repository（队友B1实现）

签名见`src/store/repository.cj`。`openRepository(StoreConfig(path:...)): Outcome<Repository>`由对方实现。

1. `read()`返回隔离快照，修改它不能改变仓库。可用`DatabaseSnapshot.fromJson(snapshot.toJson())`深拷贝。
2. `transact(change)`串行化写入，给予隔离工作副本。回调Err/异常/落盘失败时，内存和磁盘有效快照均保持旧值。写入持久化成功才发布内存新状态。
3. 所有业务集合共用一次事务，禁止另起账号/菜单专用仓库。
4. 选择已实测的SQLite。项目锁定sqlite4cj源码版本，根依赖由我维护，不新增第二套实现。实际SQL存储设计归对方；损坏数据启动失败，不能清空。
5. `onMenuCommitted(restaurantId,menuVersion)`在事务提交且锁释放后触发；回调失败不回滚已提交菜单。房间逻辑由我复检版本，不由目录模块导入房间服务。

## 账号与安全（队友B2实现）

`AccountKind.User/Merchant`在业务API区分类型；存储`kind`字符串为`user/merchant`。`StoredAuthSession`持久化tokenHash、类型、accountId、过期时间；`StoredVisitorSession`保存tokenHash与稳定visitorId。原始token只写Set-Cookie，不出现在响应JSON或日志。

`Actor`、`AuthSession`、`VisitorSession`不生成toJson，防止把Actor和Set-Cookie当公开响应。`AccountView`才是登录/注册响应。`IdentityResolver.resolve(cookies)`只解析有效服务端会话；`ensureVisitor`幂等，返回`VisitorSession(actor,setCookie)`，不创建房间成员。三种cookie独立，账号登录/退出保留访客身份。

平台`pbkdf2Sha256(passwordBytes,saltBytes,iterations:Int32)`调用OpenSSL，固定32字节输出；`PasswordDigest`保存algorithm/iterations/saltHex/hashHex。B2须选用生产工作因子、随机盐、恒定时间比较并验证错误密码/过期/退出等。测试向量iterations=1仅用于验证OpenSSL绑定，不可用于生产密码。安全随机使用`SecureRandom(priv:true)`。

用户默认设置仅长期字段。可选账号默认值只复制进新房间草稿，不提交；已有房间草稿不得被登录后的默认值覆盖。商家会话不授权用户设置。

## 联调前仍需交付

B1 Repository/演示菜单/公开目录，B2账号与默认值，B3商家写入及菜单版本回调尚未实现；对应测试由对方交付。G0网络探针不是这些业务API已实现的证明。具体路由、HTTP状态码和批次继续见两人后端交接文档。

## 2026-10-18 本侧实现更新

实际房间及推荐协议、共享新增技术字段、双端构建和DI装配方式，以根目录IMPLEMENTATION.md和生成源码为准。P1账号/菜单/持久化仍由对方交付，本侧已提供createDiningServer及提交后通知回调。自动验收38个仓颉、6个Node、8个Vitest及5条Playwright通过；账号/商家为API契约测试，实际数据模块与真实手机/模型仍待联调。
