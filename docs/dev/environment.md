# 开发环境与平台验证

实现分支为当前目录的 `main`；`docs/` 临时忽略。已有 spec 修改保持未提交，不从 Git 删除已跟踪文档。

## 安装与启动（Linux x86_64）

需仓颉 SDK 1.2.0、Node 22、curl/git/CMake/Clang15/OpenSSL 开发头文件。SDK 路径可配置：

```sh
export HUAIWEI_CANGJIE_SDK=/你的路径/cangjie
bash scripts/bootstrap-deps.sh
# 系统 Clang/OpenSSL 不适配且已安装 conda 时，可用项目内隔离工具：
bash scripts/bootstrap-deps.sh --local-tools
npm ci
bash scripts/cj.sh build -j 4
bash scripts/cj.sh exec target/release/bin/huaiwei
```

服务默认 `127.0.0.1:8080`，通过 `HUAIWEI_HOST/HUAIWEI_PORT` 覆盖。`GET /health` 是实际仓颉服务；当前尚未装配业务 API。测试 echo 仅在 `HUAIWEI_ENABLE_PROBES=true` 启用。

`scripts/cj.sh` 在子进程加载 SDK、可选 `.deps/build-tools`、stdx 动态库路径。不要要求团队复制本机绝对安装路径。首次源代码构建较慢；依赖缓存均在忽略的 `.deps/`、`build-script-cache/`、`target/`。

## 已验证选择

- cjc/cjpm/cjfmt **1.2.0**，Node **22.23.1**，npm **10.9.8**。
- 官方 stdx **v1.2.0.1**，源码提交 `89035c96e3fdb18aa43b1800fffe3763e66a810d`。GitCode 二进制下载要求认证，使用官方 GitHub 源码。其清单仍声明 1.0.5，但实际在 1.2.0 编译及 HTTP/WS/JSON/TLS 探针均通过。
- Clang **15.0.7**、项目内完整 OpenSSL **3.5.9**。系统 Clang22 对上游源码产生 `-Werror`；Fedora OpenSSL 头文件禁用的 SM4 也导致构建失败。使用官方要求的编译器和完整头文件解决，未修改加密代码或系统策略。
- zlib/boundscheck 从 OpenHarmony-v6.0-Release 源码获取，归档 SHA256 写在 bootstrap 脚本，摘要不匹配立即失败。stdx 源码构建会报告无 `.cj` 的 native 子目录警告；这不影响已经运行的探针。
- 选择 **SQLite**，适配器 `sqlite4cj` 提交 `70971c0b639ea55dcd8cfc2fc0ee03a017c38845`（源码项目 skay_caomao/sqlite4cj）。已通过真实建表、事务提交、退出进程后读取中文/unknown/整数分；无须启用 JSON 兜底。实际 Repository、事务故障恢复仍归队友 B1 实现和验证。
- 安全随机源 `stdx.crypto.crypto.SecureRandom(priv: true)`；平台 `pbkdf2Sha256` 绑定 OpenSSL `PKCS5_PBKDF2_HMAC`，RFC7914 第11节测试向量通过。账号层须自定成熟工作因子、随机盐及编码格式，不使用测试向量的迭代1作为生产配置。
- HTTPS 必须显式设置 `TlsClientConfig`，并为目标域名设置 `serverName`；默认校验使用系统根证书。`example.com` 的真实请求已通过，不关闭证书校验。后续 LLM 客户端必须从目标 URL 取得实际主机名，不能照抄探针域名。

## 验证

```sh
bash scripts/check-platform.sh
# 可选外网 TLS 探针，一般离线验收不要求外网：
HUAIWEI_PROBE_HTTPS=https://example.com bash scripts/check-platform.sh
```

包含真实 HTTP、两个独立 WS 客户端/重连、正常模式禁用探针、单调时间截止、密码散列向量、JSON/随机源和跨进程 SQLite 探针。测试运行器与服务需要本地 socket 权限；受限沙箱的 EPERM 不能当业务失败。平台验证不代表账号、房间、菜单等业务已完成。
