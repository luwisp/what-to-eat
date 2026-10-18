# Huaiwei

仓颉1.2.0的多人聚餐点菜项目。当前已实现平台和共享骨架，业务模块正在按两人分工实现。

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

另一位成员负责`src/auth/`、`src/catalog/`及实际`src/store/sqlite_repository.cj`，统一使用以上模型与Repository；不要另建服务或修改根构建配置。存储选型SQLite，适配器已锁定并通过跨进程读写探针。数据库完整记录的JSON编解码与公开输入解析有区别；账号原始token不入响应JSON，房间公开成员不能泄露他人草稿。

`docs/`按团队当前决定暂时忽略；本机的`docs/dev/environment.md`、`docs/dev/contracts.md`及spec/plan仍可供讨论，不随当前代码提交。工具缓存、运行数据、密钥与构建产物也不入Git。
