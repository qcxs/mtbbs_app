# MCP 服务端

> 适用：新增/修改 MCP 工具、调整能力开关与安全策略、排查客户端连不上。按需。

## 一句话

App 内置一个**只读** MCP 服务端（本机 Streamable HTTP），让 Trae / Claude / Cursor 这类 AI 客户端直接读取论坛内容与 App 信息。默认关闭；工具全部常驻注册，按能力开关放行。

## 为什么在 App 内起服务

| 方案 | 结论 |
|------|------|
| **Streamable HTTP（绑 127.0.0.1）** | ✅ 选定。Windows / Android 一致，AI 客户端直连本机 |
| stdio 子进程 | ❌ 客户端在 PC、App 在手机，进程模型根本连不上 |
| 绑 `0.0.0.0` 走局域网 | ❌ 令牌会暴露到局域网，等于把论坛账号开放给同网段 |

Discuz 没有官方 API，但项目已有 `lib/api/**`（HTML→JSON）与本地库，MCP 只是**换一个出口**把已有数据暴露给 AI，不新增解析逻辑。

## 协议与传输

- 依赖 `mcp_dart`（`pubspec.yaml` 锁到 `2.4.2`，见 docs/09）
- `McpProtocol.stable` → 同时讲 **2026-07-28（无状态核心）** 与 **2025-11-25（initialize 会话）**，新版客户端与仍在会话时代的老客户端都能连
- 单端点 `POST http://127.0.0.1:8765/mcp`，`enableJsonResponse: true`（本地单用户，不需要 SSE 流）
- 2026-07-28 取消了 `initialize` 握手与 `Mcp-Session-Id`，服务端因此**不需要会话存储**；`serverFactory` 每个请求创建一个 Server 实例，工具集按请求实时求值

## 分层与文件职责

```
lib/mcp/
├── mcp_server_controller.dart   唯一状态源：配置持久化、启停、端口、令牌管理、自检状态
├── mcp_authenticator.dart       令牌生成 + 回环来源校验 + 常量时间比较
├── mcp_self_test.dart           连通性自检（真实走一遍 MCP 协议）
├── mcp_sanitizer.dart           出站脱敏（黑名单兜底 + formhash 擦除 + 截断）
├── mcp_audit.dart               调用记录（内存 100 条）
├── mcp_token.dart               访问令牌模型（备注 / 创建时间 / 掩码）
├── mcp_status_notice.dart       Android 前台服务通知桥（其他平台 no-op）
├── mcp_types.dart               能力分组枚举 + 登录态快照
└── tools/
    ├── mcp_tool_registry.dart   组装 Server、统一调用包装（超时/审计/脱敏）
    ├── mcp_tool_definition.dart 工具声明 + 入参读取（McpArgs）
    ├── mcp_payloads.dart        出站数据结构（字段白名单 + 错误翻译）
    ├── mcp_resources.dart       资源与提示词注册
    └── mcp_tools_{app,forum,saved,editor,user}.dart  各能力分组的工具（user 承载 list_user_threads / list_user_friends / list_user_follows）
```

设置侧：`lib/pages/settings/models/mcp_settings.dart`（分组声明）、`lib/pages/settings/mcp_token_dialogs.dart`（令牌创建/详情）、`lib/pages/settings/mcp_help_sheet.dart`（使用帮助面板：三步接入 + 可复制配置片段 + 排障）。「能力开关」用通用模型 `ExpandableSwitchSetting`（`models/settings_model.dart`）——点按整行展开看该组具体工具名/描述，开关本身负责启停。快捷开关：`lib/widgets/dialog/mcp_quick_dialog.dart`（`showMcpQuickDialog()`，入口见「平台集成」）。

## 安全模型（四层，缺一层都不够）

1. **传输层** —— 只绑 `127.0.0.1`；开启 SDK 的 DNS rebinding 防护（`Host`/`Origin` 白名单）；`authenticator` 里再查一次**回环地址** + **Bearer 令牌**，令牌用常量时间比较；非回环来源、无令牌、错令牌一律 403。令牌可建多个（像 API Key），列表为空时**全部拒绝**（不存在"没令牌就放行"）。
2. **身份层** —— 工具复用 `ApiService().dio`，即**使用当前登录态**，所以需要登录的内容（我的收藏等）能读；但**不提供任何写操作**——没有发帖/回复/点赞/收藏工具。
3. **数据层** —— `McpPayloads` 用**字段白名单**组装响应（不是把 parse 结果整体透传），`McpSanitizer` 再兜底剥离 `cookie`/`formhash`/`registerIp`/`qq`/`realName`/写操作 URL，并擦除文本里残留的 `formhash=` 参数。
4. **审计层** —— 每次调用记一条（工具名 / 成败 / 耗时），设置页可看、可清空。

## 能力清单

| 分组 | 默认 | 工具 |
|------|------|------|
| App 信息 | 开 | `help`、`get_app_info`、`list_sites` |
| 论坛公开数据 | 开 | `list_forums`、`list_forum_threads`、`list_guide_threads`、`search_forum_threads`、`get_thread_detail`、`get_user_profile`、`list_user_threads`、`list_user_friends`、`list_user_follows`、`get_ranklist`、`get_online_users`、`get_rss_feed` |
| 只读编辑器草稿 | 开 | `list_editor_sessions`、`get_editor_draft` |
| 账号相关数据 | **关** | `list_my_favorites` |
| 本地浏览记录 | **关** | `get_browse_history` |

> `help` 是所有工具里唯一"教 AI 怎么用"的入口：返回能力清单、四类典型任务（总结最近帖子 / 总结某个账号 / 读编辑器草稿）的工具组合、参数约定与注意事项。同时 `McpServerOptions.instructions` 在连接时就会提醒"第一次先调 help"。
>
> 面向用户侧的完整工具清单就在「能力开关」里：点按任一分组行可展开，看到该组的每个工具名与描述——用于回答"这个开关到底管什么"以及"为什么我的调用被拒绝了"。

### 与 API 探针（`tool/api_probe_test.dart`）的覆盖对照

探针是开发期的接口验证工具，能力枚举很全，**可作为 MCP 的覆盖检查表**；但 MCP 是面向 AI 的正式契约，两者**不逐条对齐**（探针为"接口"，MCP 为"任务"）。新增 API 时照此表判断"要不要进 MCP"。

| 探针命令 | MCP 对应 | 备注 |
|---|---|---|
| `guide.list` | `list_guide_threads` | 已覆盖 |
| `forum.list` | `list_forum_threads` | 已覆盖 |
| `search.list` | `search_forum_threads` | 已覆盖；翻页需回传 `search_id`（见 docs/18） |
| `thread.detail` | `get_thread_detail` | 已覆盖 |
| `user.info` | `get_user_profile` | 已覆盖 |
| `my.threads` | `list_user_threads` | 已覆盖，且**支持 uid** 与 `type=reply` |
| `friend.list` | `list_user_friends` | 已覆盖，**支持 uid** |
| `follow.list` | `list_user_follows` | 已覆盖，**支持 uid** |
| `favorite.list` | `list_my_favorites` | 已覆盖（收藏不公开，仅自己） |
| `session.status` | `get_app_info` | 已覆盖（登录态/用户组） |
| `session.list` | — | 有意不覆盖：列本机 Cookie 文件名，对 AI 无意义 |
| `post.byPid` | — | 有意不覆盖：单楼层用 `get_thread_detail` 定位即可 |
| `message.system` / `message.pm` / `message.mypost` | — | **待定**：提醒与私信，敏感度高，需单独评估后再决定 |
| `debug.http` | — | **永不覆盖**：可带登录态取任意路径，等于绕过字段白名单与脱敏 |
| 写操作（`post.*`、`favorite.add/delete`、`score.*`） | — | **永不覆盖**：MCP 是只读服务，见下方决策 7 |

> MCP 另有探针没有的能力：`get_ranklist`、`get_online_users`、`get_rss_feed`、编辑器草稿、本地浏览记录、`help`——说明两者本就各自演化，"逐条对齐"没有意义。

资源：`mtbbs://app/info`、`mtbbs://forums`。提示词：`summarize_thread`（总结帖子）。

## 七个关键决策

1. **工具常驻注册，调用时才拒绝** —— MCP 客户端会缓存 `tools/list`；若"关闭就不注册"，用户每改一次开关就得让客户端重连。开关只影响"放不放行"，被拒时返回 `能力「X」已在 App 中关闭…请让用户在「设置 → MCP 服务 → 能力开关」中开启后重试`。
2. **能力分 5 组而不是一个总开关** —— 公开数据与账号数据、本地记录、草稿的敏感度差别很大，默认值也不同（账号类默认关）。
3. **白名单优先于黑名单** —— 帖子/楼层字段是显式挑出来的，黑名单只作第二道网；这样底层 model 新增字段时不会意外泄露。
4. **30 秒硬超时 + 异常翻译** —— 单次调用超时即中止（不让 AI 侧挂死拖住 App）；Discuz 对不存在的帖子直接返回 404，Dio 会抛异常，这里统一翻译成"目标不存在：帖子/用户可能已被删除，或 ID 有误（HTTP 404）"这类可读文案。
5. **正文默认返回精简 BBCode，省 AI 上下文** —— 帖子正文里大量标签只是样式（`[b]`/`[color]`/`[size]`/`[font]`…），对 AI 理解没有增量却会吃掉可观 token。所以 `get_thread_detail` 默认剔除样式标签、只留有语义的内容；需要逐字原文（还原样式、核对引用格式）时传 `full_bbcode: true`。剔除清单是 `bbcodeStyleTagIds`（`core/parser/bbcode2html.dart`），**与「设置 → 禁用样式标签」共用同一份定义**，且刻意不含 `strikethrough` —— 删除线带语义（内容被否定/作废），不属于可随意丢弃的纯样式。
6. **会发请求的工具统一走全局错峰队列** —— AI 可能一口气并发调用多个工具，短时间打出一串请求容易被站点风控当成刷量。`McpToolDefinition` 上有个 `network` 标志（**默认 true**），为 true 时调用前先过 `enqueueStagger()`——即 App 内列表/头像/表情在用的那套错峰队列（间隔即「设置 → 通用错峰间隔」），逐个放行；纯本地工具（`get_app_info`、`list_sites`、`list_forums`、编辑器草稿、浏览记录）显式标 `network: false`，不排队、不额外等待。默认取值刻意取 true：新增工具时漏标只是多等一个间隔，反之则可能让请求完全不受限。排队等待**不计入** 30 秒执行超时。
7. **不做"探针执行器"，MCP 只暴露自有契约** —— 曾考虑做 `run_probe(cmd)` 把探针命令直接透给 AI（覆盖全、维护省），最终否决：① 探针里有 `write_scenarios`（发帖/回复/收藏/评分）与 `debug.http`（带登录态取任意路径），一旦可达，只读不变式、字段白名单与 `McpSanitizer` 会**同时失守**；② 探针输出是为脚本消费设计的（`API_PROBE_BEGIN/END` 包裹、`__more__` 只留前 3 项、160 字符截断），不适合喂给 AI；③ 探针是开发工具，命令与字段随开发漂移（docs/10 自己注明"本表可能滞后"），把它当契约会让 AI 行为不稳定，审计也只剩下一个 cmd 名。正确做法是**把探针当能力地图**：照上表按"任务"补工具，每个工具仍保有独立的字段白名单 / 脱敏 / 能力分组 / 审计。两者真正共享的是 `lib/api/**/export.dart` 这一层。

## 平台集成（都由 `McpServerController` 状态驱动）

- **Android**：前台服务 + 常驻通知（`McpForegroundService` + `McpStatusNotification`）。用前台服务而非普通通知：服务随任务一起结束，通知才不会变成"服务已开启"的假状态。两条退出路径都必须显式收尾——返回键退出走 `MainActivity.onDestroy()`（`isFinishing` 时 `McpStatusNotification.stop()`），划掉任务走 `android:stopWithTask="true"`（前台服务默认**不会**随任务移除而停止，见 docs/07 #65）。应用只是切到后台（Activity 未销毁）时服务继续运行，AI 客户端仍可连接——这是前台服务存在的意义，故不在 `onStop` 里停服务。Android 13+ 先请求 `POST_NOTIFICATIONS`，授权后才启动服务（看不见通知的前台服务没有意义）。
- **Windows**：窗口标题标注 `MTBBS（已开启 MCP）`；标题栏一律由 `widgets/layout/window_title_bar.dart` 自绘（含 MCP 徽章与三个窗口按钮）。不用原生标题栏的原因见 docs/07 #61：其配色由 DWM/系统主题决定，App 无法保证可读。

### 快捷开关入口（弹窗 + 一键开关）

`showMcpQuickDialog()` —— 状态一瞥（状态点 / 端点 / 工具数 / 无令牌告警）+ **一个**开关控件（开关行），右上角可直达 `/settings/mcp`。开/关**只有开关这一处**，不再另设同语义的主按钮，避免"两套入口"。

| 入口 | 说明 |
|------|------|
| Android 常驻通知 | 点通知 → `EXTRA_TAP` → `MainActivity` → 通道 `onNotificationTap` → 弹窗 |
| Windows 标题栏徽章 | `_McpBadge` **常驻显示**（开/关两态分别为「MCP 已开启」「MCP 已关闭」），可点开弹窗快捷开关（关闭态也能点，用于快速开启） |
| 「我的」页顶部按钮 | 主题模式左侧，**一键直接开/关**（不走弹窗，toast 反馈） |

**为什么弹窗必须走 `rootNavigatorKey` 而不是调用方 context**：点通知可能发生在**冷启动首帧之前**，那时任何页面的 context 都不存在。故弹窗只用根 Overlay（与 `showToast` 同一套思路），根未就绪时先等一帧再取一次。

**冷启动的那次点击要补取**：App 没运行时点通知 = 冷启动，Dart 还没注册回调，原生先存 `pendingMcpTap`，Dart 就绪后用 `getPendingTap` 取走（与链接入站的 `getInitialUrl` 同一套"暂存 + 补取"模式）。补取刻意放在**首帧之后**，保证根 Navigator 已挂载。

**`/settings/mcp` 是第二个入口、不是第二份实现**：路由里挂的就是设置页「MCP 服务」分组用的同一个 `mcpSettings` 声明（docs/07 #54 的"两个入口、一份实现"）。

## 验证方式

```bash
flutter test test/mcp_server_test.dart        # 15 例：鉴权/只读不变量/能力开关/脱敏
flutter analyze lib test
curl -i -X POST http://127.0.0.1:8765/mcp -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'   # 无令牌应 403
```

设置页 →「MCP 服务」→「开始测试」会在本机真实走一遍协议（列工具 + 调一次）。

## 客户端配置

同一份说明也内置在 App 里：设置 →「MCP 服务」→ 顶部「使用帮助」（`showMcpHelpSheet()`），
会按当前状态提示"下一步做什么"，并提供**一键复制**的配置片段（已有令牌时直接替换为真实值）。

```json
{ "mcpServers": { "mtbbs": {
  "url": "http://127.0.0.1:8765/mcp",
  "headers": { "Authorization": "Bearer <设置页里的令牌>" }
} } }
```

## 已知限制 / 后续可做

- **Android QS 磁贴未做**（下拉栏一键开关）。
- **Windows 的 URL 打开方式未做**：Android 已注册 App Links（见 `AndroidManifest.xml`），Windows 需要在安装包里写注册表关联。
- **自定义站点不在 Android intent-filter 里**：换站/加站时要同步 manifest 的 `host`。
- **热重启（hot restart）后 MCP 可能起不来**：旧 isolate 未释放端口，`bootstrap` 会重试一次；开发期建议直接重启进程。
