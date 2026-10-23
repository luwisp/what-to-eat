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
# 如果在运行过ubuntu 24.04构建流程可以跳过这一步
bash scripts/bootstrap-deps.sh
# 如果缺少兼容的 Clang/OpenSSL，且已安装 conda，可改用：
# bash scripts/bootstrap-deps.sh --local-tools

npm ci
npm --prefix frontend ci
cp .env.example .env 
# 这里可以先配置文件再进入下一步

# 运行命令
bash scripts/dev.sh
```
默认打开 [首页](http://127.0.0.1:8080/)。`scripts/dev.sh` 会依次构建前端和后端、首次导入测试数据菜单，然后启动业务服务。

首次编译 stdx 会比较慢。停止服务按 `Ctrl+C`，再次启动仍保留原数据库内容，不会重新导入覆盖商家改动。

测试餐馆码为`LAOXIANGJI`,在主页输入即可进入

演示商家后台：访问 `/admin/`，账号 **`admin`**，密码 **`88888888`**。服务启动时会为尚未分配的 `LAOXIANGJI` 自动创建并绑定该账号，已有数据库重启后也会补齐。重复启动不会重置密码；已有 `admin` 账号保留原密码，已有餐馆归属或账号绑定其他餐馆时不改绑。

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

## 数据与菜单导入

默认数据库为 `data/runtime/juxiaobao.sqlite`，图片构建产物为 `web/menu-images/`。

```sh
# 使用快速启动流程可以不用执行以下命令
# 首次导入或有意更新示例菜单。会重新应用 Excel 配方，已有商家编辑时慎用。
python3 scripts/import-menu.py --db data/runtime/juxiaobao.sqlite

# 仅从数据库恢复缺失的图片，不改菜单或商家编辑。
python3 scripts/restore-menu-assets.py --db data/runtime/juxiaobao.sqlite
```

数据库自带一份店铺样例数据（仅作学习和参考），餐馆码为`LAOXIANGJI`

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


### 常见问题

- **403／INVALID_ORIGIN 或 WebSocket 无法连接**：核对浏览器地址与 `JUXIAOBAO_PUBLIC_BASE_URL`，端口改变后同步修改。前端开发代理场景填前端地址。
- **页面 404、图片丢失**：从仓库根目录运行启动脚本；前端单独构建后运行图片恢复命令。
- **端口占用**：调整 `.env` 中端口和公开地址；测试端口有固定用途。
- **SDK 未找到**：设置 `JUXIAOBAO_CANGJIE_SDK` 或 `CANGJIE_HOME`，SDK 根目录应包含 `envsetup.sh`。
- **`heapSize must be in range` 或随后出现 `Derive` 未定义**：仓颉宏运行时堆配置超过了机器物理内存。启动脚本默认使用 `JUXIAOBAO_CJ_HEAP_SIZE=64MB` 和单任务构建；不要在 shell 中用更大的全局 `cjHeapSize` 覆盖启动环境，需要调整时修改项目 `.env`。
- **stdx 编译或 OpenSSL 头文件错误**：先运行 `bash scripts/cj.sh prepare` 检查 C/C++ 编译器、CMake、Ninja 和 OpenSSL 头文件；Ubuntu 安装本节列出的 apt 依赖即可。兼容修复自动处理 GCC 13 的 OpenSSL resolver、JSON conversion 告警、C/C++ 警告参数和 zlib PIC，并会升级旧版补丁及清理对应 CMake 缓存；需要独立 Clang/OpenSSL 时仍可执行带 `--local-tools` 的依赖准备。
