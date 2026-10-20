# Huaiwei

仓颉1.2.0的多人聚餐点菜项目。当前已实现平台和共享骨架

```sh
export HUAIWEI_CANGJIE_SDK=/path/to/cangjie
bash scripts/bootstrap-deps.sh --local-tools  # 可选conda内Clang15/OpenSSL3.5
npm ci
bash scripts/cj.sh build -j 4
bash scripts/cj.sh exec target/release/bin/huaiwei
bash scripts/check-platform.sh
```

已有适配的Clang15/完整OpenSSL开发头文件时，bootstrap可省略`--local-tools`。首次stdx源码编译需等待；默认服务`127.0.0.1:8080`，环境变量`HUAIWEI_HOST/HUAIWEI_PORT`可覆盖。当前真实端点为`GET /health`；未完成业务API不会以原型模拟。

共享模型源在`scripts/generate-models.py`，生成`src/model/entities.cj`。模型字段改变后运行`python3 scripts/generate-models.py`。`src/model/contracts.cj`为目录/身份端口，`src/store/repository.cj`定义隔离快照与原子事务。`src/platform/http.cj`的`HttpRouter.on(method,path,handler)`支持`:id`路径参数和方法分发，`jsonResponse/jsonError`统一JSON。服务装配在`src/app/server.cj`。


## 老乡鸡菜单导入

运行 `python3 scripts/import-menu.py`，即可从 Excel 提取菜品和内嵌图片，写入 `data/runtime/huaiwei.sqlite`。支持重复导入和事务回滚，无需额外 Python 依赖。操作与现有 Repository 的衔接见 [导入说明](docs/dev/menu-import.md)。

## 算法交互调试

配置仓颉 SDK 后运行 `bash scripts/algorithm-dev.sh`，打开本机 `http://127.0.0.1:8091`。使用老乡鸡真实 SQLite 菜单运行 B2 v3 选择器，支持饭量、独立主食、动态愿望、预算档位和个人适配；保留原算法对照及 unknown/下架模拟。见 [算法实验室说明](dev/algorithm/README.md)。
