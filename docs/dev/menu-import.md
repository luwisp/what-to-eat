# Excel 菜谱 → SQLite 自动导入

入口：`scripts/import-menu.py`。仅需 Python 3 标准库，无需 pip、Excel、WPS 或联网。默认路径相对脚本所在仓库解析，任何工作目录均可运行；显式传入的相对路径相对当前工作目录解析。

## 一条命令导入老乡鸡

```sh
python3 scripts/import-menu.py
```

默认读取 `data/fixtures/老乡鸡菜谱.xlsx`，写入 `data/runtime/huaiwei.sqlite`，导出图片到 `web/menu-images/`。数据库和导出图片都是忽略的运行数据；提交源 Excel 和脚本即可在其他机器重建。

校验而不落盘：

```sh
python3 scripts/import-menu.py --dry-run
```

指定数据库、工作表、餐馆和已有商家，并导出应用快照：

```sh
python3 scripts/import-menu.py \
  --source data/fixtures/老乡鸡菜谱.xlsx \
  --db data/runtime/huaiwei.sqlite \
  --restaurant-code LAOXIANGJI --restaurant-name 老乡鸡 \
  --owner-id 已存在的商家ID \
  --snapshot-out data/runtime/snapshot.json
```

**首次导入时确定 owner-id**。默认空字符串表示未分配，不会创建商家账号或演示密码，也不表示商家已完成入驻。已有餐馆的归属不能通过导入脚本修改；重复导入时须传相同 owner-id。`source-key` 默认 `laoxiangji-menu`，同一来源重复导入保持不变；导入其他餐馆需同时指定不同的 `--source-key` 和 `--restaurant-code`。

这是**离线导入工具**：请停服务后使用，完成后再启动服务。脚本无法向运行中的仓颉内存 Repository 发布快照或向房间推送 WS 通知。菜单变化会在持久化快照中递增版本、使相关旧推荐失效并取消进行中的任务。

## 实际提取结果

当前源文件共 84 道菜、84 个有效图片引用，对应 83 张不同的内嵌图片。WPS 的 `_xlfn.DISPIMG` 公式通过 `cellimages.xml` 和关系表还原，图片按内容 SHA256 命名；不执行 Excel 公式、不访问外部图片地址。

- 4 道汤、49 道热菜/辅食/小吃、23 道主食/面点/面条/馄饨、8 道饮品。
- 金额用 Decimal 精确转整数分：9.9 → 990，3.9 → 390，拒绝负数和无法精确表示到分的金额。
- 辣度：不辣/微辣/中辣/重辣 → 0/1/2/3。
- 配料按中文或英文逗号、顿号、分号和换行拆分，去空白、去重；保留并归一 `unknown`，空食材转为 `["unknown"]`。原始食材不靠模型补全，不擅自修正原表里的名称或错字；原始行完整保存在导入记录中。
- 原文件没有可售状态或招牌标记。导入策略为 `available=true`、`isSignature=false`；这不是对当前门店库存的验证。源文件没有固定套餐，因此不凭空生成套餐。

| Excel 分类 | 应用 category |
| --- | --- |
| 热菜、辅食、小吃 | hot |
| 主食、面点、面条、馄饨 | staple |
| 汤 | soup |
| 饮料、饮品 | drink |
| 凉菜 | cold |

缺少必要表头、重复菜名、未知分类/辣度、图片公式损坏或其他公式都会明确报错。所有行解析完成后才开始数据库写入，不能导入半份菜单。

## SQLite 与现有应用的衔接

仓库目前只有 `Repository` 接口，没有 B1 的实际 SQLite Repository。因此这里明确提供一个 **SQLite 快照存储格式 v1**，并未声称默认 HTTP 服务已经读取这份菜单。

- `PRAGMA application_id = 0x48574D49`，`user_version=1`，非本格式数据库拒绝修改。
- `app_snapshot(id=1,schema_version=1,payload_json)` 是唯一业务数据源。payload 为现有模型完整 `DatabaseSnapshot`，包含全部 16 个业务集合，字段名和类型一致。
- `restaurants`、`dishes`、`menu_versions` 是基于 SQLite JSON1 的只读视图，方便 SQL 查询，不保存第二套业务状态。
- `menu_imports` 保留来源标识、源文件摘要、管理过的菜品 ID、原始行和时间；`menu_assets` 保存图片原始 BLOB，导出文件丢失后重跑即可恢复。

后续 B1 可直接用同一 SQLite 连接读取 `app_snapshot.payload_json` 并调用 `DatabaseSnapshot.fromJson`，每次 Repository 事务在 SQLite 提交新 payload 后才发布内存快照。若 B1 最终使用其他表结构，需在其 Repository 内提供适配；脚本会拒绝对不兼容库强行建表。

查看已导入数据（无需 sqlite3 命令行工具）：

```sh
python3 - <<'PY'
import sqlite3
with sqlite3.connect('data/runtime/huaiwei.sqlite') as db:
    print(db.execute('SELECT name,restaurantCode FROM restaurants').fetchall())
    print(db.execute('SELECT COUNT(*) FROM dishes').fetchone())
    print(db.execute('SELECT name,priceFen,category FROM dishes LIMIT 5').fetchall())
    print(db.execute('SELECT * FROM menu_versions').fetchall())
    print(db.execute('PRAGMA integrity_check').fetchone())
PY
```

## 重跑与失败恢复

餐馆 ID 由餐馆码稳定生成，菜品 ID 由餐馆 ID 和菜名稳定生成；源文件行重排不改变 ID。不变的菜单重复导入不增加菜品或 menuVersion；价格、食材、图片等实际字段变化使该店 menuVersion 只加 1。

来源中被移除或改名的旧菜保留并下架，避免历史房间和套餐的引用断裂。脚本保留其他来源的菜品、其他餐馆及所有账号、会话、默认设置等集合。所有数据库修改位于同一个 `BEGIN IMMEDIATE` 事务；校验/写入失败则回滚，不吞错误、不清空坏库。

图片和可选 JSON 文件是数据库提交后生成的派生文件。如果这些文件导出失败，错误会明确说明“数据库已成功提交”；修复路径后重跑可恢复。前端构建会清空 `web/`，因此应**先构建前端，再运行导入脚本**。导出的 `/menu-images/*` 已接入静态服务；Vite 开发模式同一路径代理给仓颉服务。

## 验证

```sh
python3 -m unittest discover -s tests -p 'test_menu_import.py' -v
```

6 项测试覆盖真实 Excel/WPS 图片、整数分与 unknown、重复导入、下架、菜单版本、跨模块数据保留、结果失效、数据库写入故障回滚、坏库/归属冲突和 dry-run。

此外 `tests/support/validate-import.cj` 可读取本次导出的 JSON，使用实际仓颉 `DatabaseSnapshot.fromJson` 解码并校验 84 道菜。静态图片路由由 `StaticImageTests` 验证。

本次实测：Python 6/6 通过；仓颉全套 45/45 通过（含新图片路由用例）；导出快照的仓颉实际模型解码/校验 84/84 通过；SQLite `integrity_check=ok`。重复执行真实源文件导入，返回 `changed=false, menuVersion=1`，菜品仍为 84 道。
