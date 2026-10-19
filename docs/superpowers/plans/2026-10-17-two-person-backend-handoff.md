# 两人团队分工与后端交接

**用途：** 可直接转给另一位成员。本文划分原有任务，不增加产品需求；当前只形成分工与交接约定，尚未开始实现，也未替用户联系任何人。

**2026-10-18 更新：** 食材数组支持`unknown`，表示除已列食材外仍有未知部分；按下文保存/查询/版本约定处理。推荐过滤与覆盖规则已由用户确认，仍由我负责实现，双方原分工不变。

**阅读顺序：** [spec](../specs/2026-10-16-group-dining-agent-design.md) 第3/5/6.4/6.5/9节 → 本文 → [P1详细任务与测试](2026-10-17-platform-catalog-plan.md)。全局接口见[实施总计划](2026-10-17-group-dining-implementation.md)。

## 1. 任务分配

| 我这边：前端、协作与推荐 | 另一位成员：后端数据与账号 |
| --- | --- |
| 仓颉工具链、HTTP/WS基础与服务启动 | 持久化实现、重启恢复与写入事务 |
| 共享模型/DTO、校验公共类型、Repository接口 | 两家店的演示菜单及固定套餐数据 |
| C端全部页面、商家端全部页面、扫码/二维码 | C端账号、商家账号、cookie会话、用户默认设置API |
| 房间、身份恢复、补充同行人、多人同步与权限 | 餐馆码解析、餐馆资料、菜单/套餐查询API |
| 食材匹配、套餐展开/计价、个人覆盖和规则推荐 | 商家建店、菜品/套餐增改删、归属和组分校验API |
| AI、对话、30秒降级、结果版本与确认 | 菜单版本原子递增，以及变更后的通知接口 |
| 服务装配、跨模块联调与最终验收主责 | 上述模块单测、API用例、使用说明与所属缺陷修复 |

套餐组分合法性、是否可售的数据事实归对方；按人适配、组合覆盖、推荐计价与确认归我。对方无需实现推荐算法、LLM、房间或任何前端。

## 2. 文件归属

路径均相对仓库根目录。专属目录由对应负责人维护；少量例外在表中明确列出。

| 归属 | 文件 |
| --- | --- |
| 对方 | `src/store/sqlite_repository.cj`或`src/store/json_repository.cj`、`src/store/repository_test.cj`、`src/store/seed.cj` |
| 对方 | `src/auth/`内全部实现和测试 |
| 对方 | `src/catalog/`内全部实现和测试 |
| 对方 | `data/fixtures/restaurants.json`、`docs/dev/backend-data.md` |
| 我 | `src/model/`、`src/store/repository.cj`（仅公共接口）、`docs/dev/contracts.md` |
| 我 | `src/platform/`、`src/main.cj`、`src/app/`、`src/room/`、`src/agent/` |
| 我 | `frontend/`、`data/fixtures/ingredients.json`、根构建/依赖配置、启动脚本及跨模块验收 |

`cjpm.toml`、`cjpm.lock`、根`package.json`及lock、路由总装配由我维护。对方需要新依赖时给出库、版本及用途，由我统一更新并交付新基线；不要自行另起一个服务、HTTP框架或第二套共享模型。`docs/prototypes/`和spec截图不是实现目录。

## 3. 先交付共享骨架，再并行

我先完成G0，之后双方可同时工作；原P1→P4顺序是集成依赖，不要求两个人排队完成全部阶段。

**G0由我交付：**

- 已验证能运行的仓颉1.2.0工程、配套网络库与`GET /health`、`scripts/cj.sh`；具体存储按P1/T1选择SQLite或JSON，并给出选择证据。
- `src/model/`中的实体、DTO、`Outcome<T>`/错误类型、`Actor`、输入类型；`src/store/repository.cj`中的Repository约定。
- `docs/dev/contracts.md`中的字段、接口、状态码、cookie用途和模块路由注册方式；必要的`HttpRouter`适配类型由我提供。
- 双方共同使用的基线提交/快照及启动、定向测试命令。对方机器使用自己的SDK路径，不复制我的绝对安装路径。

G0交付前，对方可阅读spec、准备测试场景和演示菜单内容；不先复制一份模型或创建另一套数据库接口。我可以在G0后先做纯规则、房间服务测试和前端契约mock；正式联调及验收仍接真实后端。

## 4. 对方任务包与交付批次

### B1：持久化、演示数据与只读菜单（P1/T2的数据服务部分）

- [ ] 按G0选型实现`openRepository(config: StoreConfig): Outcome<Repository>`，满足`read(): DatabaseSnapshot`与`transact(change): Outcome<Unit>`约定；失败写入不改变内存/磁盘有效状态。所有业务共用一个Repository，不只持久化账号和菜单。
- [ ] SQLite事务或JSON写锁/同目录原子替换可验证；重启恢复相同数据；坏数据明确失败，不静默重置数据库。测试注入写入失败并验证旧快照仍有效。
- [ ] 实现`CatalogService.getMenu(restaurantCode: String): Outcome<MenuSnapshot>`及餐馆查询；未知餐馆404；只读查询不建局、不创建Participant。
- [ ] 保存/重启恢复/菜单查询保留`ingredients`中的`unknown`，不能把它当无效食材删掉；调用我提供的`normalizeIngredients`统一处理，已知与未知并存及仅未知均合法。增加对应Repository/CatalogQuery测试。
- [ ] 演示数据2家店、主川菜馆25道完整菜品、至少1个固定套餐；含素食、各档辣度、调料/汤底和过敏过滤用例。账号初始化待B2的密码散列可用后完成，不能先写明文密码。
- [ ] 交付命令：`bash scripts/cj.sh test --filter 'RepositoryTests.*,CatalogQueryTests.*'`；附临时目录下写入→重启→读取记录。

**这批可解锁：** 我这边的真实餐馆/菜单页，以及房间/推荐服务的持久化接入。

### B2：账号、会话与用户默认设置（P1/T3）

- [ ] 两种账号分别注册/登录/退出，密码按已验证的成熟带盐慢散列存储；会话落库、过期清理、退出失效，错误输出不带凭证。
- [ ] `AuthService.resolve(cookies: String): Actor`从服务端会话恢复身份；`ensureVisitor(cookies: String): Outcome<VisitorSession>`幂等创建/恢复访客会话。VisitorSession只在后端包含Actor与可选Set-Cookie值，原始token不放响应JSON；用户、商家、访客cookie分离。访客建局/进局所用`visitorId`登录或退出后不改变；不在auth模块创建/合并房间成员。
- [ ] `DefaultSettingsService.get/put`仅读写已认证用户自己的长期字段；请求体不能指定另一个userId。更新默认值不写任何房间，也不保存今天想吃、临时文字、人数或预算。
- [ ] 提供`registerAuthRoutes(router: HttpRouter, auth: AuthService, defaults: DefaultSettingsService): Unit`；主程序由我调用。路由前缀、HTTP行为见下表。
- [ ] 交付命令：`bash scripts/cj.sh test --filter 'AuthTests.*,DefaultsTests.*'`；附注册→登录→默认值存取→退出401→公开菜单仍200的API记录。

**这批可解锁：** 我这边的正式账号页、默认设置预填、商家页面登录与访客中途登录联调。

### B3：商家菜单/固定套餐与入口信息（P1/T4）

- [ ] 一个商家只能管理一家店；餐馆码唯一、稳定；提供本店入口链接和码，二维码图片由前端生成。
- [ ] 实现菜品/套餐增改删，只允许同店组分和正整数份数；重复组分归并；被引用的菜删除409。组分下架使套餐不可推荐，不额外加套餐可售字段。
- [ ] 每次成功菜单写入在同一事务递增一次menuVersion，失败不递增；食材、价格、可售状态、套餐组成都属于变更。
- [ ] 菜单食材新增/移除`unknown`也递增menuVersion并触发同一回调；修改或导入后不得静默丢标记。测试`["土豆","unknown"]`保存/查询一致，空数组归一为`["unknown"]`，明确补全资料后移除标记会产生新版本。
- [ ] 提供`registerCatalogRoutes(router: HttpRouter, catalog: CatalogService): Unit`。目录服务接受`onMenuCommitted: (String, Int64) -> Unit`回调，参数为restaurantId/newMenuVersion，只在持久化成功且锁释放后触发；我负责连到房间结果失效。回调失败不回滚已提交菜单、不谎报菜单未写入；当前版本仍可查询，推荐提交/确认由我再次复检。
- [ ] 交付命令：`bash scripts/cj.sh test --filter 'CatalogMutationTests.*'`；附建店→录菜→套餐→公开查询→改价/下架后版本变化的API记录。

**这批可解锁：** 我这边的商家菜单编辑、二维码入口和“菜单变化使旧推荐失效”的跨模块验收。

优先交B1的可用Repository和只读菜单，不必等B2/B3全部完成才交接。每批只提交自己负责文件，并写清基线版本、变更、测试命令/结果与仍未完成项。

## 5. 共同字段与API约定

以下为实现命名，业务字段不超出spec；由我在G0同步为实际共享类型。对方不需要猜测前端会使用另一套字段名。

| 类型 | 字段 |
| --- | --- |
| Restaurant | `id, ownerId, restaurantCode, name, description` |
| Dish / DishInput | `name, description, taste, cookingMethod, priceFen, imageUrl, category, ingredients[], spiceLevel, available, isSignature`；持久化Dish另有`id, restaurantId` |
| SetMeal / SetMealInput | `name, imageUrl, components[{dishId,quantity}], priceFen`；持久化SetMeal另有`id, restaurantId` |
| UserDefaultSettings | `allergens[], avoidFoods[], dietMode, maxSpiceLevel, tastePreferences[]`；存储另有`userId, updatedAt`，写入的userId取自会话 |
| MenuSnapshot | `restaurant, menuVersion, dishes[], setMeals[]`；目录保留不可售菜供浏览，推荐层负责过滤 |
| RestaurantEntry | `restaurantCode, link`；由配置的公共地址生成`/r/:restaurantCode`，与房间邀请`/s/:roomCode`分开 |

名称、简介、口味、烹饪方式和图片引用为字符串，食材为字符串数组；available/isSignature为布尔值。分类传输值为`cold / hot / soup / staple / drink`，显示凉菜/热菜/汤/主食/饮品；辣度0–3；饮食模式`none / ovoLacto / plant`，个人辣度上限null表示都可以。所有金额整数分、数量正整数、时间戳统一Unix毫秒。食材含调料/汤底，不增加过敏原表、资料状态或饮食模式匹配标记。

`ingredients`例：`["土豆","青椒","unknown"]`表示已知土豆/青椒，剩余食材不详；`["unknown"]`表示全部不明。共享`normalizeIngredients(values: Array<String>): Array<String>`去首尾空白、合并大小写/重复unknown；空数组/全空白归一为`["unknown"]`。不另增完整性字段，套餐从各组分菜读取原数组。商家表单的“不明食材”点选与C端中文提示由我实现。

我这边的推荐规则：unknown不影响无食材限制者的适配；有不吃/素食要求者不计覆盖；任一已提交成员有过敏时整桌排除unknown菜及包含它的固定套餐。无过敏时，套餐其他完整适配组分仍可计覆盖；AI不能补齐未知配方。这些判断不放进对方的目录/存储层，目录仍返回可浏览的完整菜单数据。

| API | 返回/行为 |
| --- | --- |
| `POST /api/visitor/session` | 204，幂等设置/恢复HttpOnly访客cookie；不创建Participant、不要求登录，原始token不放JSON |
| `POST /api/user/register`、`POST /api/merchant/register` | `{login,password}`；201返回脱敏AccountView；不会自动登录，登录另建会话 |
| `POST /api/user/login`、`POST /api/merchant/login` | 200返回脱敏AccountView，设置各自cookie |
| `POST /api/user/logout`、`POST /api/merchant/logout` | 204，清账号cookie，不清访客身份 |
| `GET /api/user/me`、`GET /api/merchant/me` | 已登录200；未登录401，前端按访客处理 |
| `GET /api/user/default-settings` | 已登录200；首次无记录返回空过敏/不吃/偏好、dietMode=none、maxSpiceLevel=null；未登录401 |
| `PUT /api/user/default-settings` | 200返回已保存默认值；只接受长期字段，客户端userId不授权代写；不接受愿望/文字/预算字段 |
| `GET /api/restaurants/:restaurantCode` | 200返回餐馆；不存在404，不建局 |
| `GET /api/restaurants/:restaurantCode/menu` | 200返回MenuSnapshot；不存在404 |
| `GET /api/merchant/restaurant` | 200返回`{restaurant,entry}`；未建店404 |
| `POST /api/merchant/restaurant`、`PUT /api/merchant/restaurant` | 201/200返回`{restaurant,entry}`；建第二家店409 |
| `POST /api/merchant/dishes`、`POST /api/merchant/set-meals` | 201返回保存实体；归属由会话确定 |
| `PUT /api/merchant/dishes/:id`、`PUT /api/merchant/set-meals/:id` | 200返回保存实体；跨店403 |
| `DELETE /api/merchant/dishes/:id`、`DELETE /api/merchant/set-meals/:id` | 204；被引用菜409；无效/越权不能改版本 |

错误统一`{error:{code,message}}`；输入非法400、未登录401、无权限403、不存在404、冲突409。对方在`docs/dev/backend-data.md`给出样例和错误码，我同步共同接口及前端；接口变动同时更新调用方和用例。

## 6. 联调与交付边界

- G0之后我维护共享接口；对方维护模块说明和所属实现。发现模型不够时提出具体字段/签名及原因，统一改一次，不在各模块加同名替代类型。
- 对方的auth路由负责会话端点；目录路由使用已解析Actor校验归属；公共中间件/路由挂载和WS鉴权装配由我负责。
- 菜单版本事实由对方保证，房间失效广播/推荐复检/确认由我保证；不会要求对方处理WebSocket房间。
- 演示数据调整归对方，规则食材字典归我；最终测试发现问题按上述文件归属修复，再由我复跑整体流程。
- 当前只有设计与计划，G0、B1/B2/B3均未完成。工作区/分支及具体开始执行的方法留待下一步讨论；此文可先交给另一位成员评估与准备。
