# 10-API 探针使用规范

> 适用：用探针真实请求 API（只读验证、调试），新增场景前先看第 7 节。按需。

> 本规范供 AI 与人类快速上手 API 只读探针：以"命令 + 参数"方式真实请求 Discuz API，
> 复用 App 的 Cookie 登录态，输出机器可解析的 JSON 协议。

## 1. 架构

```
调用层（跨平台，无 shell 依赖）
  flutter test tool/api_probe_test.dart --dart-define=cmd=<命令> --dart-define=key=value

规范层（自描述）
  cmd=help            → 动态生成全部命令/参数/示例/踩坑提示（永不过期）
  docs/10-API探针使用规范.md（本文件）→ 架构、上手引导、踩坑记录

实现层（Dart，复杂逻辑全部在此，shell 只做转发）
  tool/api_bootstrap.dart  模拟 App 初始化序列（真实 HttpOverrides + Windows 证书 + 站点 + Cookie）
  tool/api_scenarios.dart  场景聚合器（合并 scenarios/ 下三个子模块，对外接口不变）
  tool/scenarios/scenario_types.dart   ApiScenario 类型定义
  tool/scenarios/read_scenarios.dart   只读场景（含 Cookie 目录扫描）
  tool/scenarios/write_scenarios.dart  写操作场景（发帖/评论/回复/修改/评分/收藏）
  tool/scenarios/debug_scenarios.dart  调试场景（debug.http）
  tool/api_probe_test.dart 入口：解析 --dart-define、执行场景、输出协议
```

- 曾有一个 `api_probe.ps1` 便捷层，因 Windows-only 且 PowerShell 5.1 存在编码/解析坑，
  已移除。跨平台一律直接调用 `flutter test`（见 help 的 `invoke` 字段）。
- 每个场景都真实调用 API 层 export 函数（`lib/api/**/export.dart`），非 mock，
  解析管线与 App 完全一致。

## 2. 快速上手（三步）

```bash
# 1) 查看全部命令、参数、示例、踩坑提示
flutter test tool/api_probe_test.dart --dart-define=cmd=help

# 2) 查看本机已持久化的登录状态（游客 Cookie + 各账号名）
flutter test tool/api_probe_test.dart --dart-define=cmd=session.list

# 3) 执行具体命令（无需登录的示例）
flutter test tool/api_probe_test.dart --dart-define=cmd=guide.list --dart-define=view=newthread --dart-define=log=off
```

## 3. 全局参数

| 参数 | 说明 |
|---|---|
| `cmd` | 场景命令（默认 `session.list`），见第 4 节清单 |
| `account` | 登录账号名（空 = 游客）。先跑 `session.list` 查看可用账号，再追加 `account=<账号名>` |
| `site` | 站点（索引数字或名称，空 = 第一个站点），如 `site=1` 切到吾爱破解 |
| `baseUrl` | 指定任意站点 URL（测试站等不在默认列表中的站点）；传入时站点列表替换为单站，Cookie 目录自动跟随 host |
| `siteName` | 与 `baseUrl` 配合的站点名（空则用域名） |
| `cookie` | 临时注入 Cookie，格式 `k=v,k2=v2`（也兼容浏览器复制出来的 `k=v; k2=v2`）。写入**当前账号**的 CookieJar，用于绕过人机验证 / 防盗链，如 `cookie=acw_sc__v2=<40位hex>` |
| `header` | 临时注入请求头，格式 `Name:Value,Name2:Value2`，加进 Dio 默认头，如 `header=Referer:https://bbs.binmt.cc/` |
| `log` | `off` / `info` / `debug`（默认 `info`；`off` 只输出协议 JSON，`debug` 输出 PARSE 明细） |
| 其余键 | 透传给场景的 `params`（见 help 中每个场景的 `params` 字段） |

## 4. 场景命令清单

| 命令 | 说明 | 需登录 |
|---|---|---|
| `session.list` | 查看本机 Cookie 目录（游客 + 各账号） | 否 |
| `session.status` | 当前会话用户状态（uid/用户名/积分/用户组） | 否 |
| `guide.list` | 导读列表（默认移动端 UA），`view=newthread/newreply/digest` | 否 |
| `forum.list` | 版块帖子列表，`fid=*`（必填） | 否 |
| `thread.detail` | 帖子详情（楼主 + 楼层，自动截断），`tid=*` | 否 |
| `post.byPid` | 按 pid 取单个楼层（viewpid 接口），`tid=*`/`pid=*` | 否 |
| `user.info` | 用户空间信息，`uid`/`username` 二选一，空则查自己 | 否 |
| `friend.list` | 好友列表，`uid`（空=自己） | 否 |
| `follow.list` | 关注/粉丝列表，`type=*`（following/follower），`uid`（空=自己） | 否 |
| `favorite.list` | 收藏列表（含 favid，供删除用） | 是 |
| `message.system` | 系统提醒列表 | 是 |
| `message.pm` | 私人消息列表 | 是 |
| `message.mypost` | 帖子提醒列表，`type=post/at` | 是 |
| `my.threads` | 我的主题列表（默认移动端 UA） | 是 |
| `debug.http` | 调试：GET 指定路径，输出状态码/响应头/原始正文（携带当前会话 Cookie） | 否 |

> 完整参数与说明以 `cmd=help` 实时输出为准（本表可能滞后）。

## 5. 调用规范与参数约定

- **输出协议**：`=== API_PROBE_BEGIN ===` + JSON + `=== API_PROBE_END ===`。
  - `ok=true` = 管线无异常；`result.success` = 业务层结果。
  - 缺登录态时 `blocked=true` + `reminder` 提示先运行 App 登录。
- **大结果压缩**：列表保留前 3 项 + `__more__`，长字符串截断 160 字符
  （`debug.http` 等 `raw` 场景除外，由场景自己控制长度）。
- **参数值禁止包含** `& | ; " 空格` 等特殊字符：
  - `&` 在 PowerShell→cmd 传递时会被拆成命令分隔符；
  - `"` 会被 shell 剥离（JSON 方案不可行）。
- **`debug.http` 的 query 参数**：用 `q=k1=v1,k2=v2` 逗号分隔（逗号在各类 shell 中均安全），
  禁止直接传含 `&` 的完整 URL：
  ```
  --dart-define=cmd=debug.http --dart-define=path=/forum.php --dart-define=q=mod=guide,index=1,view=newthread
  ```
- **登录态复用**：探针读取 `%APPDATA%\qcxs\mtbbs_debug\cookies\{host}`（与 App 共享目录）。
  首次使用前先运行一次 App（`flutter run -d windows`）并登录生成 Cookie；
  无 Cookie 时 `needsLogin` 场景会自动拦截并提示。

### 5.1 站点开启人机验证 / 防火墙时

探针**无法自行通过**人机验证，两条路都堵死：

- 没有 JS 引擎 —— 挑战页（如阿里云 ESA 的 `acw_sc__v2`）靠 JS 计算并写入 Cookie，Dart 侧执行不了；
- 没有界面 —— `VerificationGate` 在无 UI 上下文时直接放弃，不会弹浏览器。

表现：请求返回 200 但正文是"非论坛页"（几 KB 的挑战页，而非论坛 HTML）。探针会检测到并：

- 日志打 `[DIO] … 命中非论坛页（人机验证/防火墙拦截）`；
- 输出协议里追加 `reminder`，写明补救步骤。

出路是**复用已通过验证的浏览器里的那个 Cookie**：

```bash
# 浏览器已过验证 → F12 → Application → Cookies → 复制 acw_sc__v2 的值
flutter test tool/api_probe_test.dart --dart-define=cmd=guide.list --dart-define=cookie=acw_sc__v2=<40位hex>
```

该 Cookie 会写进当前账号的 CookieJar（与 App 共用），有效期内后续探测不用重复传。
也可先正常跑一次 App（走弹窗验证，见 docs/01「Referer 模拟策略」旁的验证流程），
让 Cookie 自动回流后再跑探针。

## 6. 踩坑记录（历史教训，勿重蹈）

| 坑 | 表现 | 规避 |
|---|---|---|
| `&` 被 cmd 拆分 | URL 直接传参被拆成多条命令 | 用 `path=` + `q=` 逗号分隔 |
| 双引号被 shell 剥离 | JSON 参数引号丢失，解析静默失败 | 弃用 JSON，用逗号分隔 `k=v` |
| `String.fromEnvironment` 循环变量失效 | 运行时求值取默认值，参数丢失 | 必须逐键显式 `const` 读取 |
| args 白名单固定 | 新参数键没读进 map，请求缺参数 | 新键需在 `args` map 里显式声明 |
| PowerShell 5.1 中文注释编码 | 无 BOM UTF-8 按 ANSI 解码，脚本解析失败 | ps1 已移除；如需脚本保持纯 ASCII |
| flutter_test 自动装 mock HttpOverrides | 所有请求返回 400 | bootstrap 里用真实 `HttpOverrides.global` 覆盖 |
| Dio 对 Map 数据不自动加 Content-Type | PHP 收不到 `$_POST`，表单校验失败 | 显式 `Headers.formUrlEncodedContentType` |
| 站点开了人机验证，探针"请求成功却解析不出内容" | 200 + 几 KB 非论坛页（如阿里云 JS 挑战页） | 探针检测并给 `reminder`；用 `cookie=acw_sc__v2=<值>` 补凭证（见 5.1） |
| 注入 Cookie 不生效 | cookie_jar 按 `domain` 归档，`dart:io` 的 `Cookie` 默认无 domain | 注入时显式 `..domain='.{host}'`（与 `cookie_sync.dart` 同款） |
| `cookie` 值含非法字符导致整次探测失败 | `dart:io` 的 `Cookie` 按 RFC 6265 严格校验（值含 `,` 会抛） | 单条 try/catch 跳过并记 WARN，不影响其余（见 docs/07 #26） |

## 7. 扩展指南（新增 API 场景）

新增一个只读 API 的测试：

1. 在 [api_scenarios.dart](../tool/api_scenarios.dart) 注册一条 `ApiScenario`：
   - `desc`：说明用途（AI 可读）；
   - `params`：参数说明，`*` 前缀 = 必填（自动校验）；
   - `needsLogin`：需登录设 true（无 Cookie 自动拦截）；
   - `run`：调用对应 `lib/api/**/export.dart` 函数。
2. 若参数键不在 [api_probe_test.dart](../tool/api_probe_test.dart) 的 `args` 白名单，
   需显式补一行 `const String.fromEnvironment('键')`。
3. 跑 `cmd=help` 确认新场景已自动出现在清单，再实际执行验证。

开发新 API（http/parse/export 未完成时）的调试循环：

```
debug.http 拿原始响应（含登录态 Cookie） → 对照 Chrome MCP 渲染 DOM → 写 parse → 注册场景验证
```

## 8. 相关文件

| 文件 | 作用 |
|---|---|
| `tool/api_probe_test.dart` | 探针入口：参数解析、执行、协议输出、help 自描述 |
| `tool/api_scenarios.dart` | 场景聚合器（合并 `tool/scenarios/` 三个子模块） |
| `tool/scenarios/scenario_types.dart` | `ApiScenario` 类型定义 |
| `tool/scenarios/read_scenarios.dart` | 只读场景 + Cookie 目录扫描 |
| `tool/scenarios/write_scenarios.dart` | 写操作场景 |
| `tool/scenarios/debug_scenarios.dart` | 调试场景（`debug.http`） |
| `tool/api_bootstrap.dart` | 初始化序列（真实网络 + Windows 证书 + 站点 + Cookie 切换 + 临时 cookie/header 注入 + 拦截页探测） |
| `lib/api/**/export.dart` | 被测 API 层（http 请求 + parse 解析） |
| `lib/core/app/app_paths.dart` | Cookie 目录定位（Windows 分支） |
