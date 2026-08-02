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
  tool/api_scenarios.dart  场景注册表（命令 → 描述/参数/needsLogin/run）
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
| `user.info` | 用户空间信息，`uid`/`username` 二选一，空则查自己 | 否 |
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
| `tool/api_scenarios.dart` | 场景注册表 + Cookie 目录扫描 |
| `tool/api_bootstrap.dart` | 初始化序列（真实网络 + Windows 证书 + 站点 + Cookie 切换） |
| `lib/api/**/export.dart` | 被测 API 层（http 请求 + parse 解析） |
| `lib/core/app/app_paths.dart` | Cookie 目录定位（Windows 分支） |
