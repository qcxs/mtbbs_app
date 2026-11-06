# MCP 服务端

> 适用：新增/修改 MCP 工具、调整能力开关与安全策略、排查客户端连不上。按需。

## 一句话

App 内置一个**只读** MCP 服务端（本机 Streamable HTTP），让 Trae / Claude / Cursor 这类 AI 客户端直接读取论坛内容与 App 信息。默认关闭；工具全部常驻注册，按能力开关放行。

## 为什么在 App 内起服务

| 方案 | 结论 |
|------|------|
| **Streamable HTTP（默认绑 127.0.0.1）** | ✅ 选定。Windows / Android 一致，AI 客户端直连本机 |
| stdio 子进程 | ❌ 客户端在 PC、App 在手机，进程模型根本连不上 |
| 绑 `0.0.0.0` 走局域网 | ⚠️ 默认**不**开；作为**可选**设置「允许非本机连接」（默认关、需二次确认）。开启后仍强制 Bearer 令牌 + Host 白名单，用于"App 与 AI 客户端不在同一台设备"的场景 |

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
├── mcp_status_notice.dart       Android / 鸿蒙的常驻通知桥（其他平台 no-op）
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

1. **传输层** —— 默认只绑 `127.0.0.1`，`authenticator` 只接受**回环**来源；设置「允许非本机连接」开启后才监听 `0.0.0.0`，并把 DNS-rebinding 的 `Host` 白名单扩为**本机各 IPv4 + 主机名**、`authenticator` 改收非回环来源（见 `McpServerController.allowRemote` / `McpAuthenticator.acceptsRemote`）。无论哪种模式都叠加 SDK 的 DNS rebinding 防护（`Host`/`Origin`）与 **Bearer 令牌**（常量时间比较）；无令牌、错令牌一律 403。令牌可建多个（像 API Key），列表为空时**全部拒绝**（不存在"没令牌就放行"）。开启局域网访问时设置页会二次确认、且无令牌时给出告警。
2. **身份层** —— 工具默认复用 `ApiService().dio`，即**使用当前站点与当前登录态**，所以需要登录的内容（我的收藏等）能读；但**不提供任何写操作**——没有发帖/回复/点赞/收藏工具。跨站点读取默认开启（公开信息）；换账号视角默认关闭，见下方「跨站点与身份权限」。
3. **数据层** —— `McpPayloads` 用**字段白名单**组装响应（不是把 parse 结果整体透传），`McpSanitizer` 再兜底剥离 `cookie`/`formhash`/`registerIp`/`qq`/`realName`/写操作 URL，并擦除文本里残留的 `formhash=` 参数。
4. **审计层** —— 每次调用记一条（工具名 / 成败 / 耗时），设置页可看、可清空。

## 能力清单

| 分组 | 默认 | 工具 |
|------|------|------|
| App 信息 | 开 | `help`、`get_app_info`、`list_sites` |
| 论坛公开数据 | 开 | `list_forums`、`list_forum_threads`、`list_guide_threads`、`search_forum_threads`、`get_thread_detail`、`get_user_profile`、`list_user_threads`、`list_user_friends`、`list_user_follows`、`list_wall_messages`、`list_groups`、`list_group_forums`、`get_ranklist`、`get_online_users`、`get_rss_feed` |
| 只读编辑器草稿 | 开 | `list_editor_sessions`、`get_editor_draft` |
| 本地工具 | 开 | `codec_text`（Base64 / URL / Hex / MD5 / SHA1 / SHA256，纯本地计算） |
| App 导航 | 开 | `open_app_page`（打开帖子 / 用户 / 版块 / 搜索 / 导读 / 首页） |
| 账号相关数据 | **关** | `list_my_favorites`、`list_credit_log`、`list_notifications` |
| 本地浏览记录 | **关** | `get_browse_history` |

> **`get_thread_detail` 的 `source` 参数**：`auto`（默认，有效缓存优先、未命中再联网）/ `network`（强制最新）/ `cache`（只读缓存，未命中返回 `cacheMiss=true` 且不发请求）。缓存命中时响应带 `source=cache` 与 `cache{kind,stale,cachedPages,totalPages,expiresAt,…}`、`cacheNote`；缓存通常只含访问过的页码，深页缺失时 `auto` 回退联网、`cache` 明确返回缺失页。实现见 `lib/mcp/tools/mcp_tools_forum.dart`，缓存本体见 docs/24。
>
> **`open_app_page` 的边界**：只开放内容页白名单（`thread` / `user` / `forum` / `search` / `guide` / `home`），刻意不开放设置、编辑器、内置浏览器与私信页；它不写数据但会切换当前页面，故 `readOnlyHint=false`（全服务唯一）。导航回调由 `main.dart` 在路由创建后注入（`McpServerController.bindNavigator`），MCP 层不直接依赖 UI；App 未就绪或处于后台时返回可读错误。
>
> **`get_app_info` 的返回**：`versionName` / `versionCode` / `commitHash`、`build{isBeta,channel,builtAt}`、
> `platform`、`links{repo,releases,issues}`、`site{name,host,baseUrl,browseMode}`、`account`（登录态）。
> 用于判断版本、排查构建差异、告诉用户去哪看更新；不含 token / cookie / formhash。
>
> `help` 是所有工具里唯一"教 AI 怎么用"的入口：返回能力清单、典型任务（总结最近帖子 / 总结某个账号 / 读编辑器草稿 / 搜索论坛内容 / 浏览圈子与留言板 / 低时效缓存读帖 / 编解码 / App 内跳转 / 跨站点读取）的工具组合、参数约定与注意事项。同时 `McpServerOptions.instructions` 在连接时就会提醒"第一次先调 help"。
>
> 面向用户侧的完整工具清单就在「能力开关」里：点按任一分组行可展开，看到该组的每个工具名与描述——用于回答"这个开关到底管什么"以及"为什么我的调用被拒绝了"。
>
> 所有工具都额外支持一个**通用入参 `browse_mode`**（`mobile` / `desktop`）：本次调用临时换用「浏览模式」（UA 换模板），省略 = 跟随 App 当前站点设置。用途：某套模板解析异常时换 UA 复测。实现见 `core/app/browse_mode.dart`、docs/03；**仅本次调用有效**（Zone 级，并发调用不串味）。
>
> **跨站点 / 换账号视角（`site` / `account`）**：`site` 属公开信息，**默认开启**；`account` 会以其它账号的登录态读取，**默认关闭**，需用户手动开启。关闭时对应入参不出现在 schema 里，硬传会被明确拒绝。
>
> **`mobile` 是白名单**（只有少数接口支持移动端，且必定有 PC 保底）：仅 `list_forum_threads` / `list_guide_threads` / `search_forum_threads` / `list_user_threads` / `get_user_profile` 支持；其余工具为 PC-only，传 `mobile` 会返回明确错误（提示改用 `desktop` 或省略），避免"移动模板解析出错数据"被 AI 当成正常结果。白名单由各工具声明 `McpToolDefinition.mobileSupported`（默认 false）、`test/browse_mode_test.dart` 锁定。

### 跨站点与身份权限

设置页「跨站点与身份」下有两个开关：**跨站点默认开启**（站点是公开信息），**切换用户视角默认关闭**（用户身份是敏感信息，需手动开启）。

| 开关 | 默认 | 持久化键 | 开启后 AI 可传 | 边界 |
|---|---|---|---|---|
| 允许跨站点访问 | **开** | `mcpAllowCrossSite` | `site=<域名或站点名>`：读取**已配置站点**的公开数据 | 只对已配置站点生效；未匹配到会返回可用站点列表 |
| 允许切换用户视角 | **关** | `mcpAllowAccountSwitch` | `account=<账号名>`：以该站点**已登录账号**的 Cookie 只读 | 只换读取视角；能读到该账号可见的私密内容，故开启前有风险确认 |

关闭的权限不会出现在工具 schema 里；即使 AI 硬传也会被拒绝并提示用户去开启（不会静默忽略）。

行为与实现要点：

- **按次生效，不改全局状态**：`site` / `account` 通过 Zone 传入本次调用（`lib/mcp/mcp_scope.dart`），
  不切换 App 当前站点、不切换当前登录账号；并发调用互不影响。
- **工具层统一读取**：`McpScope.effectiveDio` / `effectiveHost` / `effectiveUid` 分别替代
  `ApiService().dio` / `SiteStore.instance.host` / 当前 uid，因此读帖缓存、`get_app_info`、`list_forums`
  都会自然跟随目标站点与目标账号。
- **请求元信息跟随目标站点**：`RequestSiteOverride` 让 `resolveRequestUserAgent()` / `resolveRequestCharset()`
  在跨站时返回目标站点的 UA 与编码（如 GBK 站点搜索关键词仍能正确编码），见 `core/app/browse_mode.dart`。
- **当前站点换账号不新开罐**：若 `account` 等于当前登录账号，直接沿用全局 Dio；否则用
  `ApiService().scopedDio(...)` 打开该账号独立 Cookie 罐。当前站点的**游客**罐与全局罐目录相同，
  `SessionRegistry.refreshHost` 因此不为当前站点建作用域会话（见 docs/27）。
- **只读**：MCP 仍然没有任何写操作工具；`open_app_page` 跨站只支持帖子 / 用户 / 搜索页，
  版块、导读、首页会被拒绝（路由器在这些页面上会改送内置浏览器）。
- **`help` 如实报告权限**：`help` 返回 `permissions{crossSite, accountSwitch}`，
  并说明"未开启时不要反复重试，应提示用户去设置里开启"。
- 权限不涉及监听地址，**切换开关无需重启 MCP 服务**：`serverFactory` 每请求重建。

### 与 API 探针（`tool/api_probe_test.dart`）的覆盖对照

探针是开发期的接口验证工具，能力枚举很全，**可作为 MCP 的覆盖检查表**；但 MCP 是面向 AI 的正式契约，两者**不逐条对齐**（探针为"接口"，MCP 为"任务"）。新增 API 时照此表判断"要不要进 MCP"。

> 下表会随功能漂移，已提供自动检查：`flutter test tool/api_probe_test.dart --dart-define=cmd=coverage` 输出「场景 → 工具」映射、有工具无场景、有场景无工具三组清单（实现见 `tool/scenarios/mcp_coverage.dart`）。新增探针场景或 MCP 工具后先跑它。

| 探针命令 | MCP 对应 | 备注 |
|---|---|---|
| `forum.nav` | `list_forums` | 已覆盖（版块表缓存的来源） |
| `guide.list` | `list_guide_threads` | 已覆盖 |
| `forum.list` | `list_forum_threads` | 已覆盖 |
| `search.list` | `search_forum_threads` | 已覆盖；翻页需回传 `search_id`（见 docs/18） |
| `thread.detail` | `get_thread_detail` | 已覆盖；`source=auto` 默认先读本地缓存 |
| `cache.list` / `cache.thread` | `get_thread_detail` | 本地缓存场景（不联网），验证快照 → payload 的字段对齐 |
| `user.info` | `get_user_profile` | 已覆盖 |
| `my.threads` | `list_user_threads` | 已覆盖，且**支持 uid** 与 `type=reply` |
| `friend.list` | `list_user_friends` | 已覆盖，**支持 uid** |
| `follow.list` | `list_user_follows` | 已覆盖，**支持 uid** |
| `favorite.list` | `list_my_favorites` | 已覆盖（收藏不公开，仅自己） |
| `session.status` | `get_app_info` | 已覆盖（登录态/用户组） |
| `ranklist.thread` / `ranklist.member` / `ranklist.forum` | `get_ranklist` | 已覆盖（`type=thread/member/forum`） |
| `online.list` | `get_online_users` | 已覆盖 |
| `rss.list` | `get_rss_feed` | 已覆盖 |
| `group.index` / `group.category` | `list_groups` / `list_group_forums` | 已覆盖（圈内帖子用 `list_forum_threads`，fid 传 gid） |
| `wall.list` | `list_wall_messages` | 已覆盖 |
| `credit.log` | `list_credit_log` | 已覆盖（`accountData`，默认关） |
| `message.system` / `message.manage` / `message.interactive` / `message.mypost` | `list_notifications` | 已覆盖（`accountData`，默认关） |
| `session.list` | — | 有意不覆盖：列本机 Cookie 文件名，对 AI 无意义 |
| `post.byPid` / `post.findTid` | — | 有意不覆盖：单楼层用 `get_thread_detail` 定位即可 |
| `notice.counts` | — | 有意不覆盖：未读计数属 App 内徽标逻辑，AI 读内容用 `list_notifications` |
| `site.cdn` / `darkroom.list` | — | 有意不覆盖：CDN 探测是 App 内部逻辑；小黑屋面向管理，暂不暴露 |
| `message.pm` / `message.pm.view` | — | **待定**：私信敏感度高，需单独评估后再决定 |
| `debug.http` | — | **永不覆盖**：可带登录态取任意路径，等于绕过字段白名单与脱敏 |
| 写操作（`post.*`、`favorite.add/delete`、`score.*`、`wall.post/edit/delete`、`message.pm.send`） | — | **永不覆盖**：MCP 是只读服务，见下方决策 7 |

> MCP 另有探针没有的"本地能力"：编辑器草稿、本地浏览记录、`help`、`codec_text`、`open_app_page`——说明两者本就各自演化，"逐条对齐"没有意义。

资源：`mtbbs://app/info`、`mtbbs://forums`。提示词：`summarize_thread`（总结帖子）。

## 七个关键决策

1. **工具常驻注册，调用时才拒绝** —— MCP 客户端会缓存 `tools/list`；若"关闭就不注册"，用户每改一次开关就得让客户端重连。开关只影响"放不放行"，被拒时返回 `能力「X」已在 App 中关闭…请让用户在「设置 → MCP 服务 → 能力开关」中开启后重试`。
2. **能力分 7 组而不是一个总开关** —— 公开数据、账号数据、本地记录、草稿、本地计算与页面导航的敏感度差别很大，默认值也不同（账号类默认关；编解码与导航只涉及本地能力，默认开）。
3. **白名单优先于黑名单** —— 帖子/楼层字段是显式挑出来的，黑名单只作第二道网；这样底层 model 新增字段时不会意外泄露。
4. **30 秒硬超时 + 异常翻译** —— 单次调用超时即中止（不让 AI 侧挂死拖住 App）；Discuz 对不存在的帖子直接返回 404，Dio 会抛异常，这里统一翻译成"目标不存在：帖子/用户可能已被删除，或 ID 有误（HTTP 404）"这类可读文案。
5. **正文默认返回精简 BBCode，省 AI 上下文** —— 帖子正文里大量标签只是样式（`[b]`/`[color]`/`[size]`/`[font]`…），对 AI 理解没有增量却会吃掉可观 token。所以 `get_thread_detail` 默认剔除样式标签、只留有语义的内容；需要逐字原文（还原样式、核对引用格式）时传 `full_bbcode: true`。剔除清单是 `bbcodeStyleTagIds`（`core/parser/bbcode2html.dart`），**与「设置 → 禁用样式标签」共用同一份定义**，且刻意不含 `strikethrough` —— 删除线带语义（内容被否定/作废），不属于可随意丢弃的纯样式。

   **超长楼层分片**：单层正文超过 `max_bbcode_chars`（默认 6000，上限 50000）时不再"一截了之"——该层返回 `bbcodeTotalChars` + `bbcodeNextOffset`，AI 用 `bbcode_offset` 续读同一层；顶层 `note` 也会写明续读方法。两条硬约束：① 偏移量作用于**输出后的文本**（精简版与 `full_bbcode=true` 长度不同），续读必须沿用相同的 `full_bbcode`，故响应回显 `bbcodeMode` 供对齐；② 分片按"层"生效，不要用一次调用铺开全部楼层。这是"AI 上下文有限"与"帖子可能极长"的正解：按需分段，而不是一次塞满或直接丢弃。
6. **会发请求的工具统一走全局错峰队列** —— AI 可能一口气并发调用多个工具，短时间打出一串请求容易被站点风控当成刷量。`McpToolDefinition` 上有个 `network` 标志（**默认 true**），为 true 时调用前先过 `enqueueStagger()`——即 App 内列表/头像/表情在用的那套错峰队列（间隔即「设置 → 通用错峰间隔」），逐个放行；纯本地工具（`get_app_info`、`list_sites`、`list_forums`、编辑器草稿、浏览记录、`codec_text`、`open_app_page`）显式标 `network: false`，不排队、不额外等待。默认取值刻意取 true：新增工具时漏标只是多等一个间隔，反之则可能让请求完全不受限。排队等待**不计入** 30 秒执行超时。**降低请求量还有一招**：`get_thread_detail` 默认 `source=auto`，命中未过期缓存时完全不发 HTTP。
7. **不做"探针执行器"，MCP 只暴露自有契约** —— 曾考虑做 `run_probe(cmd)` 把探针命令直接透给 AI（覆盖全、维护省），最终否决：① 探针里有 `write_scenarios`（发帖/回复/收藏/评分）与 `debug.http`（带登录态取任意路径），一旦可达，只读不变式、字段白名单与 `McpSanitizer` 会**同时失守**；② 探针输出是为脚本消费设计的（`API_PROBE_BEGIN/END` 包裹、`__more__` 只留前 3 项、160 字符截断），不适合喂给 AI；③ 探针是开发工具，命令与字段随开发漂移（docs/10 自己注明"本表可能滞后"），把它当契约会让 AI 行为不稳定，审计也只剩下一个 cmd 名。正确做法是**把探针当能力地图**：照上表按"任务"补工具，每个工具仍保有独立的字段白名单 / 脱敏 / 能力分组 / 审计。两者真正共享的是 `lib/api/**/export.dart` 这一层。

## 平台集成（都由 `McpServerController` 状态驱动）

- **Android**：前台服务 + 常驻通知（`McpForegroundService` + `McpStatusNotification`）。用前台服务而非普通通知：服务随任务一起结束，通知才不会变成"服务已开启"的假状态。两条退出路径都必须显式收尾——返回键退出走 `MainActivity.onDestroy()`（`isFinishing` 时 `McpStatusNotification.stop()`），划掉任务走 `android:stopWithTask="true"`（前台服务默认**不会**随任务移除而停止，见 docs/07 #65）。应用只是切到后台（Activity 未销毁）时服务继续运行，AI 客户端仍可连接——这是前台服务存在的意义，故不在 `onStop` 里停服务。Android 13+ 先请求 `POST_NOTIFICATIONS`，授权后才启动服务（看不见通知的前台服务没有意义）。
- **Windows**：窗口标题标注 `MTBBS（已开启 MCP）`；标题栏一律由 `widgets/layout/window_title_bar.dart` 自绘（含 MCP 徽章与三个窗口按钮）。不用原生标题栏的原因见 docs/07 #61：其配色由 DWM/系统主题决定，App 无法保证可读。
- **鸿蒙**：`notificationManager` 常驻通知（`SERVICE_INFORMATION` 槽位 + `isOngoing`），原生实现在鸿蒙仓库 `ohos/entry/src/main/ets/plugins/McpStatusNotice.ets`（Dart 侧只维护通道契约，见该文件注释）。通知的 Want 携带 `mcp_tap` 参数回到 `EntryAbility`，再由原生调通道 `onNotificationTap` 弹快捷开关；冷启动时原生先暂存，Dart 首帧后 `getPendingTap` 补取。首次发布时原生调 `requestEnableNotification` 申请通知权限，被拒则静默跳过。平台判定在 Dart 侧用 `Platform.operatingSystem == 'ohos'` 字符串（官方 Flutter 没有 `TargetPlatform.ohos`）。

  **前台限定**：鸿蒙没有能承载「本机 HTTP 服务」的长时任务类型（`DATA_TRANSFER` 要求持续上报进度、10 分钟不更新会被系统取消；`TASK_KEEPING` 仅 2in1 或需受限 ACL），因此 MCP 只在 App 前台可用。`EntryAbility.onBackground()` 会撤销常驻通知、`onForeground()` 恢复，避免出现「通知说服务已开启、实际连不上」的假状态（与 Android 前台服务的语义不同）。

### 快捷开关入口（弹窗 + 一键开关）

`showMcpQuickDialog()` —— 状态一瞥（状态点 / 端点 / 工具数 / 无令牌告警）+ **一个**开关控件（开关行），右上角可直达 `/settings/mcp`。开/关**只有开关这一处**，不再另设同语义的主按钮，避免"两套入口"。

| 入口 | 说明 |
|------|------|
| Android 常驻通知 | 点通知 → `EXTRA_TAP` → `MainActivity` → 通道 `onNotificationTap` → 弹窗 |
| 鸿蒙常驻通知 | 点通知 → Want 参数 `mcp_tap` → `EntryAbility` → 通道 `onNotificationTap` → 弹窗（冷启动由 `getPendingTap` 补取） |
| Windows 标题栏徽章 | `_McpBadge` **常驻显示**（开/关两态分别为「MCP 已开启」「MCP 已关闭」），可点开弹窗快捷开关（关闭态也能点，用于快速开启） |
| 「我的」页顶部按钮 | 主题模式左侧，**一键直接开/关**（不走弹窗，toast 反馈） |

**为什么弹窗必须走 `rootNavigatorKey` 而不是调用方 context**：点通知可能发生在**冷启动首帧之前**，那时任何页面的 context 都不存在。故弹窗只用根 Overlay（与 `showToast` 同一套思路），根未就绪时先等一帧再取一次。

**冷启动的那次点击要补取**：App 没运行时点通知 = 冷启动，Dart 还没注册回调，原生先存 `pendingMcpTap`，Dart 就绪后用 `getPendingTap` 取走（与链接入站的 `getInitialUrl` 同一套"暂存 + 补取"模式）。补取刻意放在**首帧之后**，保证根 Navigator 已挂载。

**`/settings/mcp` 是第二个入口、不是第二份实现**：路由里挂的就是设置页「MCP 服务」分组用的同一个 `mcpSettings` 声明（docs/07 #54 的"两个入口、一份实现"）。

## 验证方式

```bash
flutter test test/mcp_server_test.dart        # 24 例：鉴权/只读不变量/能力开关/脱敏/正文分片
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
- **页面导航只在前台可见**：MCP 服务运行在 App 进程内，`open_app_page` 用 `router.push` 切换页面；App 在后台时调用不会把它带到前台，需配合平台侧"打开应用"能力（Android 已有 intent，Windows/鸿蒙未做）。
