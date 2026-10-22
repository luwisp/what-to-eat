# 聚小宝 · Juxiaobao

仓颉 1.2.0 + Vue 3 的多人聚餐点菜应用。业务服务使用 SQLite 保存账号、餐馆菜单、聚餐局和推荐结果

## 前置依赖

- 仓颉 1.2.0
- Node.js 22
- Python 3

源码构建还需要 CMake、Ninja、Clang 15 和完整的 OpenSSL 开发头文件。

已测试平台：fedora44、ubuntu24.04

### Ubuntu 24.04 构建

先安装系统提供的构建依赖（Node.js 22 和仓颉 SDK 仍按前置依赖准备）：

```sh
sudo apt update
sudo apt install -y build-essential cmake ninja-build libssl-dev python3 git curl ca-certificates

# 新环境首次下载依赖；已有 .deps 也可重复执行，不覆盖应用数据。
bash scripts/bootstrap-deps.sh
# 可单独检查和修复原生构建环境；dev.sh 也会自动执行。
bash scripts/cj.sh prepare
```
前端超过 500 kB 的提示是体积警告，不影响启动。

## 快速启动

在项目根目录执行。当前验证环境为 Linux x86_64、。
```sh
export JUXIAOBAO_CANGJIE_SDK=/你的SDK目录/cangjie

# 下载锁定版本的 stdx、sqlite4cj 及原生依赖源码。
bash scripts/bootstrap-deps.sh
# 如果缺少兼容的 Clang/OpenSSL，且已安装 conda，可改用：
# bash scripts/bootstrap-deps.sh --local-tools

npm ci
npm --prefix frontend ci
cp .env.example .env 
# 这里可以先配置文件再进入下一步
bash scripts/dev.sh
```
默认打开 [首页](http://127.0.0.1:8080/)。`scripts/dev.sh` 会依次构建前端和后端、首次导入测试数据菜单，然后启动业务服务。

首次编译 stdx 会比较慢。停止服务按 `Ctrl+C`，再次启动仍保留原数据库内容，不会重新导入覆盖商家改动。


### 配置文件

`.env` 由启动脚本读取，端口和地址在其中修改。`JUXIAOBAO_PUBLIC_BASE_URL` 必须与浏览器实际访问地址一致，包括协议、主机名和端口；

`localhost` 与 `127.0.0.1` 不能混用。

配置参考：
```dotenv
JUXIAOBAO_HOST=127.0.0.1
JUXIAOBAO_PORT=8092
JUXIAOBAO_PUBLIC_BASE_URL=http://127.0.0.1:8092
JUXIAOBAO_CJ_HEAP_SIZE=64MB
JUXIAOBAO_BUILD_JOBS=1
JUXIAOBAO_DB_PATH=data/runtime/juxiaobao.sqlite

DEEPSEEK_API_KEY=你的密钥
DEEPSEEK_BASE_URL=https://api.deepseek.com
DEEPSEEK_MODEL=deepseek-flash
```
密钥或模型名称为空时使用规则推荐，文字整理和 AI 聊天不可用。

不读取项目 `.env`、单独指定配置时：
```sh
JUXIAOBAO_ENV_FILE=/dev/null JUXIAOBAO_PORT=8081 \
  JUXIAOBAO_PUBLIC_BASE_URL=http://127.0.0.1:8081 bash scripts/dev.sh
```

### 页面入口


| 路径 | 用途 |
| --- | --- |
| `/` | 首页：扫码、输入餐馆码或同站邀请链接；右上角进入账号页 |
| `/r/:code/menu` | 菜单、图片、单点和套餐，标记想吃 |
| `/s/:code` | 聚餐概览、邀请、成员状态、预算、推荐及调整 |
| `/s/:code/preferences` | 从成员列表进入本人的要求编辑，食量、辣度为滑竿 |
| `/s/:code/result` | 独立图文方案页，查看菜品、修改份数、对话和确认 |
| `/account` | 消费者注册、登录、退出和默认设置 |
| `/admin/` | 商家注册、登录、餐馆资料、菜单、套餐和餐馆二维码 |
| `/health` | 服务健康检查，正常返回 `{"status":"ok","sdk":"1.2.0"}` |
| `/api/capabilities` | 查看本次服务是否启用了 AI |

## 账号与默认设置

### 消费者

1. 从首页右上角“我的”进入 `/account`，选择注册，成功后再登录。登录／注册表单下方的小字可进入商家工作台。
2. 账号不能为空且不能含空白或控制字符；密码至少 8 字节。建议联调使用不少于 8 位的英文数字密码。
3. 登录后可编辑“用户名”（展示名字，最多40字；登录账号不变），并保存食量、过敏、不吃、饮食方式、接受辣度及口味喜好。新加入聚餐局时使用该用户名，已有成员名字不自动覆盖。退出按钮独立放在设置卡片下方。
4. 新建或首次填写时带入默认设置；已有本局草稿和已提交要求优先，不会因修改账号默认设置而自动覆盖。
5. 本次想吃的具体菜、套餐、食材和文字补充不保存为账号默认值。

未登录也能看菜单、建局、加入、填写和点菜。

### 商家

1. 从首页右上角“我的”进入 `/account`，在登录／注册表单下方的小字进入商家工作台。
2. 注册商家账号，登录后创建自己的餐馆。可编辑名称和简介，管理菜品价格、图片地址、配方、辣度、上下架、分类、招牌及推荐角色资料，并维护套餐组分和价格。
3. 新增和编辑在弹窗内完成。菜品和套餐图片使用上传方框，支持选择或拖入JPG、PNG、WebP，自动缩小并压缩，上传后可预览、替换或移除。
4. 餐馆入口链接及二维码在后台生成，扫码即可进入聚餐界面。

消费者与商家是独立账号域：可使用相同账号名分别注册

## 一桌用餐的流程

1. 从首页进入餐馆，可先标记想吃的菜和套餐，也可直接填写人数、可选人均预算后建局。
2. 建局后从顶部“邀请同行人”打开居中二维码弹窗，链接和复制按钮同排，可用关闭按钮、Esc 或背景关闭；“看菜单”在邀请旁边。不需要先填完自己的要求。同一浏览器共享访客身份；模拟不同人请用不同浏览器配置或无痕会话。
3. 聚餐页集中展示成员。点“我”后面的填写／编辑进入要求页，代填、编辑和移除同行人也在同一成员列表操作；不再使用概览／要求／菜单三栏切换。只存草稿不会计为已填写，提交后返回这一桌。人数和预算放在可展开的设置中。
4. 点击“确认方案”，页面显示搭配中的加载状态，完成后进入独立图文结果页。系统结合各人限制、食量、主食、愿望和全桌预算生成方案；每个人有适配菜即可，不要求每道菜适合所有人。
5. 默认每人一份米饭。选面条、馄饨或菜单中的对应单人主食会替代自动米饭；明确又选米饭时保留米饭。食量小／正常／大／特别大对应估算 0.5／1／1.5／2 份热菜需求，主食、汤、小吃、饮品单独计算。
6. 点击“修改这桌方案”，直接在原菜品卡片中删菜、增减份数；“＋ 从菜单加菜”进入原菜单，返回后保存并重新校验。修改尚未保存时暂不能同时发送 AI 调整；取消则恢复原方案。“看看每个人怎么吃”用成员卡片展示热菜份量、主食及适配菜品。也可使用快捷调整，启用 AI 时可文字调整。缺口或冲突会展示，不会通过放宽限制强行完成。
7. 确认方案后需要重开才能再改。需求、人数、预算或菜单发生变化会使原推荐失效，需重新推荐。

食量、辣度使用滑竿；口味和饮食方式紧凑排列。“不吃”选项末尾的“＋ 其他”按需展开输入，“过敏”为低强调的可展开入口。“想吃”中的固定喜好直接选择；“按食材选”可以展开搜索本店食材；末尾“＋ 菜单选菜”标记具体菜、小吃、饮品和套餐。高级主食与辣度愿望字段保留给推荐端和 AI 建议，不逐项铺在表单中。

配方末尾的 `unknown` 表示剩余食材未知。无食材限制者仍可推荐；有不吃或素食限制时不计为确定适配；整桌有人过敏时会排除此类菜。食材关联匹配仍有覆盖范围限制，复杂过敏场景和全面的品牌饮料配方识别尚未完成。

## AI 配置与边界

文字随个人要求一起提交，推荐时 AI 接收所有已提交者的文字与选项，结合全桌菜单搭配；要求页不再放置单独的“整理文字”按钮。不吃与过敏仍应在对应选项中确认，文字不能放宽这些限制。结果页右下角“找点菜员聊聊”展开悬浮对话，回复与调整过程中保持展开，对话区自行滚动，整页不再重复跳转到顶部；模型推荐仍经过服务端的菜单、价格、配方、适配与预算校验。AI 可调用 `search_menu` 按招牌、口味、做法、食材、价格或辣度检索本店可售菜，调用 `get_dish` / `get_set_meal` 读取细节，再用 `edit_plan` 直接增加、移除或设置当前方案的份数。未操作的条目保留，结果仍由服务器重算和校验；AI 工具完成后继续生成贴合当前消息的简短回复；普通问候、菜品咨询或澄清只追加对话，不替换推荐方案，方案没有变化时不再提示“已调整”。这些工具只改这桌方案，不修改商家资料。支持点菜相关问答、简单闲聊及澄清；流式文字回复尚未实现。

## 数据与菜单导入

默认数据库为 `data/runtime/juxiaobao.sqlite`，图片构建产物为 `web/menu-images/`。首次使用新名称启动时，若新库不存在且同目录有旧版默认库，脚本会用 SQLite 备份接口复制全部数据到新库，保留原库；已有新库不会被覆盖。旧浏览器要求草稿也会在首次读取时迁移。环境变量、包名和执行文件已统一为 `JUXIAOBAO_*` / `juxiaobao`，旧 `.env` 中的同名前缀需同步替换；SDK 变量现为 `JUXIAOBAO_CANGJIE_SDK`。商家上传图片默认保存在数据库路径加 `.uploads` 后缀的独立目录中，例如 `data/runtime/juxiaobao.sqlite.uploads/`，不会被前端构建清理；可通过 `JUXIAOBAO_IMAGE_DIR` 指定目录。运行数据和 `.env` 不提交到 Git。备份或迁移数据时先停止应用，同时保存 SQLite 数据库和上传图片目录。

```sh
# 首次导入或有意更新示例菜单。会重新应用 Excel 配方，已有商家编辑时慎用。
python3 scripts/import-menu.py --db data/runtime/juxiaobao.sqlite

# 仅从数据库恢复缺失的图片，不改菜单或商家编辑。
python3 scripts/restore-menu-assets.py --db data/runtime/juxiaobao.sqlite
```

导入从 `data/fixtures/老乡鸡菜谱.xlsx` 提取菜品和内嵌图片，角色及份量补充事实来自 `data/fixtures/meal-annotations.json`，无需额外 Python 包。`--owner-id` 只能指定数据库中已存在的商家，并且不能借重复导入转移既有餐馆归属。导入支持重复执行和事务回滚；现有数据库启动时不自动重导菜单。

## 开发、检查与其他运行方式

安装浏览器测试运行时：

```sh
npm --prefix frontend exec -- playwright install chromium
```

完整检查：

```sh
bash scripts/check.sh
```

| 命令 | 用途 |
| --- | --- |
| `npm --prefix frontend run test -- --run` | 前端单元测试 |
| `bash scripts/build-integration-server.sh` 后运行 `npm --prefix frontend run test:e2e` | 组件级浏览器回归，使用测试适配器 |
| `npm --prefix frontend run test:e2e:full` | 真实 SQLite、账号、商家、聚餐和推荐浏览器联调，需先构建后端 |
| `node --test tests/auth-integration.mjs` | 从空数据库验证正式启动脚本、账号隔离、退出及服务重启持久化 |
| `bash scripts/check-platform.sh` | 额外平台、加密、SQLite 和服务探针检查 |

需要前端热更新时，先运行正式业务服务，再在另一个终端执行（后端端口按实际配置调整）：

```sh
JUXIAOBAO_API_ORIGIN=http://127.0.0.1:8080 npm --prefix frontend run dev -- --port 5173
```

此时后端 `JUXIAOBAO_PUBLIC_BASE_URL` 要设为浏览器实际使用的 `http://127.0.0.1:5173`，以匹配写入和 WebSocket 来源。

`bash scripts/dev.sh --component-demo` 是独立的 `TEST` 组件演示，使用内存菜单和测试身份，重启会清空房间，不能用于验证真实账号和商家菜单写入。

直接运行 `bash scripts/cj.sh exec target/release/bin/juxiaobao` 只启动已编译服务，不会读取 `.env`、构建前端、导入新库或恢复图片；需事先完成这些步骤并导出所需环境变量。一般联调使用 `scripts/dev.sh`。

### 代码入口

- `src/main.cj` → `src/app/server.cj`：服务配置与业务装配。
- `src/auth/`：消费者／商家认证、Cookie 会话和用户默认设置。
- `src/catalog/`：餐馆、菜单和套餐写入及归属校验。
- `src/room/`：多人房间、WebSocket、推荐作业和状态变更。
- `src/agent/`：规则、份量选择器、AI 工具与校验。
- `src/store/`：Repository 与 SQLite 快照事务。
- `frontend/src/`：消费者和商家 Vue 页面。
- `scripts/generate-models.py`：共享模型源；修改字段后生成 `src/model/entities.cj` 和前端契约。

### 常见问题

- **403／INVALID_ORIGIN 或 WebSocket 无法连接**：核对浏览器地址与 `JUXIAOBAO_PUBLIC_BASE_URL`，端口改变后同步修改。前端开发代理场景填前端地址。
- **页面 404、图片丢失**：从仓库根目录运行启动脚本；前端单独构建后运行图片恢复命令。
- **端口占用**：调整 `.env` 中端口和公开地址；测试端口有固定用途。
- **SDK 未找到**：设置 `JUXIAOBAO_CANGJIE_SDK` 或 `CANGJIE_HOME`，SDK 根目录应包含 `envsetup.sh`。
- **`heapSize must be in range` 或随后出现 `Derive` 未定义**：仓颉宏运行时堆配置超过了机器物理内存。启动脚本默认使用 `JUXIAOBAO_CJ_HEAP_SIZE=64MB` 和单任务构建；不要在 shell 中用更大的全局 `cjHeapSize` 覆盖启动环境，需要调整时修改项目 `.env`。
- **stdx 编译或 OpenSSL 头文件错误**：先运行 `bash scripts/cj.sh prepare` 检查 C/C++ 编译器、CMake、Ninja 和 OpenSSL 头文件；Ubuntu 安装本节列出的 apt 依赖即可。兼容修复自动处理 GCC 13 的 OpenSSL resolver、JSON conversion 告警、C/C++ 警告参数和 zlib PIC，并会升级旧版补丁及清理对应 CMake 缓存；需要独立 Clang/OpenSSL 时仍可执行带 `--local-tools` 的依赖准备。
