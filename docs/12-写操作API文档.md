# 12-写操作 API 文档（发帖/评论/回复/修改）

> 适用：发帖/评论/回复/修改四种写操作（formhash/posttime/Content-Type 协议）。按需。

> 来源：测试站 discuz.qcxs.top 实测（2026-08-02，账号 user1）。
> 探针场景：`post.new` / `post.reply`（含 reppid）/ `post.edit` / `post.captcha`，见 `tool/api_scenarios.dart`。

## 0. 核心机制（四种操作通用）

| 字段 | 说明 |
|---|---|
| `formhash` | Discuz CSRF 令牌，**必填**。来自页面隐藏 `<input name="formhash">`，每次会话不同 |
| `posttime` | 时间戳，来自页面隐藏 `<input name="posttime">` |
| `inajax=1` | 提交 URL 参数，Discuz 返回 inajax 格式响应（XML/文本） |
| `Content-Type` | **必须显式** `application/x-www-form-urlencoded`（Dio 对 Map 不自动加头，否则 Discuz 收不到 `$_POST` 报"表单验证串不符"） |

**fid 规则**：只有发帖需要真实 fid；评论/回复/修改由 tid 推导（URL 里 `fid=` 空值与无 fid 效果相同，服务端忽略）。

**GBK 站点（52pojie）的表单编码**：Discuz 按**站点字符集**解码 POST 字段，而 Dio 对 `Map` data 固定按 UTF-8 编码 → 中文正文/标题会存成乱码（实测评论成功但内容乱码）。拦截器 `_encodeFormBody`（`services/api_service_client.dart`）在 `Content-Type` 为 form-urlencoded 且站点字符集为 `gbk/gb2312` 时，用 `encodeFormBodyForSite` 把 Map 手工编码成 GBK 百分号串再发送；其余站点保持原 Map。新增写操作只要走站点 Dio + form-urlencoded，就自动生效。

**通用流程**（两步）：
1. GET 对应页面 → 提取 `formhash`/`posttime`（及 fid）
2. POST 提交端点 + form-urlencoded 表单

## 1. 发帖 — fid

| 项 | 值 |
|---|---|
| 加载页 | `GET /forum.php?mod=post&action=newthread&fid={fid}` |
| 提交端点 | `POST /forum.php?mod=post&action=newthread&fid={fid}&topicsubmit=yes&inajax=1` |
| 必填参数 | `formhash` `posttime` `topicsubmit=yes` `subject`(标题) `message`(内容) |
| 可选参数 | `attachnew[{aid}][description]`（可多个）：把**已上传的附件**绑定到帖子。**正文 `message` 里没有引用到的附件，会被展示在正文末尾**；不传则附件不绑定，帖子页完全看不到（实测：同一文件，带/不带 attachnew 两帖，前者有文件名、后者没有）。见 `parseAttachNew` |
| 探针场景 | `post.new`（fid、subject、message 必填） |

成功响应：`非常感谢，您的主题已发布…`，返回新 `tid`。

**tid/pid 提取（`parseSubmitResponse`）**：按"可靠性递减"链式取值，两字段各自独立，不要只认 `tid=`：

| 来源（优先级从高到低） | tid | pid |
|---|---|---|
| `succeedhandle_` 第 3 参 JS 对象 | `'tid':'…'` | `'pid':'…'` |
| redirect 查询串 | `tid=` / `ptid=` | `pid=` / `#pid` |
| 伪静态路径 | `thread-{tid}-…html` | — |

兼容两种站点风格：查询串式（`forum.php?mod=viewthread&tid=…`）与伪静态式（`thread-{tid}-1-1.html`，如 MT 论坛）。见 docs/07 #95。

**客户端落点（发帖后自动跳转，见 `editor_page_actions.dart`）**：

| 结果 | 跳转 |
|---|---|
| 解析到 `tid` | 直接打开新帖 `/thread/{tid}` |
| 未解析到 `tid`（响应里无任何 tid 线索，极少数） | 打开 `/my-threads`（刚发布的必是第一条） |
| 需审核（`needsApproval`，或提示文案含「审核」） | 什么都不做，仅退出编辑器 |

## 2. 评论 — tid

| 项 | 值 |
|---|---|
| 加载页 | `GET /forum.php?mod=post&action=reply&fid=2&tid={tid}` |
| 提交端点 | `POST /forum.php?mod=post&action=reply&fid={fid}&tid={tid}&replysubmit=yes&inajax=1` |
| 必填参数 | `formhash` `posttime` `message` `replysubmit=yes` |
| 探针场景 | `post.reply`（tid、message 必填；**不带 reppid**） |

成功响应：`非常感谢，回复发布成功…`，返回 `pid`。

## 3. 回复某条评论 — tid + pid(reppid)

| 项 | 值 |
|---|---|
| 加载页 | `GET /forum.php?mod=post&action=reply&fid=2&tid={tid}&repquote={pid}`（repquote=被回复评论的 pid） |
| 提交端点 | 同评论，表单额外带 `reppid={pid}` 与 `reppost={pid}` |
| 必填参数 | `formhash` `posttime` `message` `replysubmit=yes` `reppid` `reppost` |
| 探针场景 | `post.reply` 加 `reppid={pid}` |

**注意**：探针 args 键是 `reppid`，缺失时静默降级为普通评论（曾因此误判成功）。Discuz 用 reppid 做楼层定位与通知，不生成引用块。

## 4. 修改帖子/评论 — tid + pid

| 项 | 值 |
|---|---|
| 加载页 | `GET /forum.php?mod=post&action=edit&fid={fid}&tid={tid}&pid={pid}` |
| 提交端点 | `POST /forum.php?mod=post&action=edit&fid={fid}&tid={tid}&pid={pid}&editsubmit=yes&inajax=1&formhash={formhash}` |
| 必填参数 | `formhash` `posttime` `subject` `message` `fid` `tid` `pid` `page=1` `editsubmit=yes` |
| 探针场景 | `post.edit`（tid、pid、message 必填；subject 改帖子时用） |

**帖子与评论同一张表**：楼主帖就是 `pid=楼主的 pid`（第一个），所以改帖子和改评论都走 `action=edit` + tid + pid，仅 pid 不同。

**成功判定**：Discuz 编辑成功返回 **301/302**，`Location` 含 `viewthread`；失败返回页面内错误文案（"无权/权限/不能"等关键词）。

## 5. 实测结果（discuz.qcxs.top / user1）

| 操作 | 命令 | 结果 |
|---|---|---|
| 发帖 | `post.new fid=2 subject=探针发帖测试 message=…` | tid=19 ✓ |
| 评论 | `post.reply tid=18 message=…` | pid=61/62/63 ✓ |
| 回复评论 | `post.reply tid=18 reppid=62 message=…` | pid=64 ✓ |
| 修改评论 | `post.edit tid=18 pid=62 message=修改后…` | 内容更新 + 编辑标记 ✓ |
| 修改楼主帖 | `post.edit tid=18 pid=55 subject=… message=…` | 标题+内容均更新 ✓ |

## 6. 发送私信 — 收件人 touid

| 项 | 值 |
|---|---|
| 加载页 | `GET /home.php?mod=spacecp&ac=pm&op=showmsg&touid={touid}`（取 formhash） |
| 提交端点 | `POST /home.php?mod=spacecp&ac=pm&op=send&touid={touid}&pmsubmit=yes&inajax=1` |
| 必填参数 | `formhash` `touid` `pmsubmit=true` `message` |
| 探针场景 | `message.pm.send`（touid、message 必填） |
| 代码 | `lib/api/home/pm/{http,parse,export}.dart`（`sendPm` / `getPmView`） |

要点：

- **收件人统一走 `touid`**：Discuz 的 `op=send` 对 `touid`（新会话/回复）与 `pmid`（回复某条）分别处理，1:1 私信按对方 uid 归组，二者等价，故只用 `touid` 即可覆盖两种场景（`submitcheck('pmsubmit')` 要求 POST + formhash 匹配）。
- **`inajax=1` 返回 XML**：`succeedhandle_pmsend('…', '操作成功', {'pmid':…})` / `errorhandle_pmsend('两次发送短消息太快…')`，可直接交给 `parseSubmitResponse`。
- **formhash 来源**：会话页（`subop=view`）的回复表单里就有；但**会话为空时该表单不渲染**（模板条件 `$touid && $list`），所以 `sendPm` 在未显式传入 formhash 时会拉取 `op=showmsg` 页兜底。
- **限流**：站点有发送间隔（实测约 60s），过频返回"两次发送短消息太快，请稍候再发送"。
- **会话详情（只读）**：`GET /home.php?mod=space&do=pm&subop=view&touid={touid}`。`page` 从**最旧页 1** 递增到最新，**不带 page = 最新页**；分页栏 `pmmulti` 只输出「上一页/下一页」链接，故解析结果给 `olderPage`/`newerPage`/`hasOlder` 而非页码总数。正文经 UCenter `uccode` 渲染成 HTML，用 `Html2BBCode` 还原（与帖子同源）。
- **实时轮询**：Discuz **没有**"增量拉新消息"接口（`op=checknewpm` 只更新 `newpm` 状态位，不返回内容），客户端只能周期重拉最新一页、按 `pmid` 去重后追加（`PmChatPage` 每 **15s** 一次，前台+页面可见时才跑）。整页重拉是本页最贵的请求，间隔即请求量：**5s 时约 720 次/小时，足以触发站点 WAF 频次限制（403）**；因此实现上还做了：连续失败按 30s→60s→120s 退避（成功即复位）、收到 **403/429 立即暂停自动刷新**并由用户手动刷新解除、`_loadNewest` 单飞（轮询/发送/刷新不叠同一请求）、表情元数据只在进页时加载一次（失败不在每轮重试）。
- **已读**：加载会话页本身就会清除该会话的未读标记（实测 `message.pm` 的 `isNew` 由 `true` → `false`），无需额外的"标记已读"请求。

## 7. 人机验证（seccode / secqaa，可选）

站点开启「发帖/回复验证码」时，发帖/回复/编辑页会渲染验证区。Discuz 有**两种并列形态**，以页面实际字段为准，不要按站点写死：

| 形态 | 开关变量 | 页面标记 | 提交字段 |
|---|---|---|---|
| 图片验证码 **seccode** | `seccodecheck = 1` | `input[name=seccodehash]`（旧版 `seccode`）/ `img[src*=mod=seccode]` / `span[id^=seccode_]` | `seccodehash`（或 `seccode`）+ `seccodemodid` + `seccodeverify` |
| 验证问答 **secqaa** | `secqaacheck = 1` | `input[name=secqaahash]` / `span[id^=secqaa_]`（如 52pojie 的 `secqaa_qS0`） | `secqaahash` + `secanswer`（无 modid） |

两种都可能只输出了**占位 span**（桌面模板由 JS 动态注入输入区）：`<span id="seccode_<hash>">` / `<span id="secqaa_<hash>">`，hash 就是 id 后缀。`#seccheck` 容器在两种模式下都存在，**不能**用它判断是否要验证。

提交时空值一律不提交，避免给未开启验证码的站点带脏参数。

### 7.1 图片验证码（seccode）

**图片与刷新（实测 discuz.qcxs.top）**：

- 图片必须用站点 Dio 请求（同 cookie / UA），且**必须显式带 `Referer`**：该端点会校验来源页，缺失时返回 13 字节 `Access Denied`（text/html 而非图片，会被客户端判为加载失败）。响应 `image/png`；**不能走图片缓存**，也不能用 `CachedNetworkImage`。
- **首次加载与「换一个」都要先调**：`GET /misc.php?mod=seccode&action=update&idhash={hash}&modid={modId}&{ts}` 返回一段 JS，里面带合法 `misc.php?mod=seccode&update={n}&idhash={hash}`，解析后再用新地址取图。`modid` 必须与提交的 `seccodemodid` 一致（发帖/回复为 `forum::post`），否则会话里的验证码模块为空，提交会被判为验证码错误。
- **直接构造图片地址不可行**：服务端会校验 `update` 令牌，自造 `update={timestamp}` 实测返回 `Access Denied`。`buildSeccodeImageUrl` 仅作 `action=update` 响应解析失败时的兜底。
- 校验失败返回 `抱歉，验证码填写错误`。验证码**一次性**，失败后旧码失效，必须清空输入并换图重试。

### 7.2 验证问答（secqaa，实测 52pojie）

- 页面只给占位 `span#secqaa_<hash>` + `<script>updatesecqaa('<hash>', …)</script>`，**题面和输入框都不在 HTML 里**。
- 题面必须调 `GET /misc.php?mod=secqaa&action=update&idhash={hash}&modid=forum::post&{ts}`：响应是 `application/javascript`，题面夹在 JS 拼接串的 `sectplcode[2] + '题面' + sectplcode[3]` 之间。该请求同时把新题写入会话，`secqaahash` 才能被服务端认可。
- 站点是 GBK（52pojie）时，题面按站点字符集解码（Dio 按 `content-type` 的 charset 处理），否则中文乱码。
- 提交：`secqaahash` + `secanswer`。校验失败文案含「验证问答」（如 `验证问答回答错误`），同样**一次性**，失败后换题重试。
- 题面里可能自带「答案：xxx」提示，那是站点后台配置的题目内容，不是通用规律。客户端据此提供「填充答案」按钮（`parseSecqaaAnswer` 提取，取不到则不显示）。

**客户端链路**：

| 层 | 实现 |
|---|---|
| 解析 | `PageFetcher.parsePage` → `seccodeHash/…`、`secqaaHash/secqaaModId/secqaaQuestion`、`seccodeRequired` / `secqaaRequired` / `captchaRequired` |
| API | `lib/api/forum/seccode/{http,parse,export}.dart`（取图 / 换图 / JS 地址解析）；`lib/api/forum/secqaa/{http,parse,export}.dart`（取题面 / JS 题面解析） |
| 状态 | `EditorSession` 持有 `seccodeCtl` / `seccodeImage` / `secqaaCtl` / `secqaaQuestion`；`loadCaptcha()` 按页面类型分发，`resetCaptcha()` 同时清空两种 |
| UI | `CaptchaField` / `CaptchaFields`（`widgets/editor/captcha_field.dart`），完整编辑器与帖子页迷你编辑器共用；验证失败时**不收起**迷你编辑器，允许原地重试 |
| 提交 | `post/http.dart` 统一追加 `_seccodeFields` / `_secqaaFields`；`editor_submit.dart` 从 `pageData` 读取 |

## 8. 关注 / 取消关注 — uid

Discuz 把「关注」叫「收听」，按钮文案随模板不同（PC 资料页「收听TA / 取消收听」，
克米移动模板「关注」/ 已关注仅显示图标）。客户端统一显示「关注 / 已关注」。

| 项 | 关注 | 取消关注 |
|---|---|---|
| 端点 | `GET /home.php?mod=spacecp&ac=follow&op=add&hash={formhash}&fuid={uid}&inajax=1` | `GET /home.php?mod=spacecp&ac=follow&op=del&fuid={uid}&inajax=1` |
| 必填参数 | `hash`（= formhash）、`fuid` | `fuid`（服务端不校验 formhash） |
| 探针场景 | `follow.add`（uid 必填，formhash 可空） | `follow.del`（uid 必填） |
| 代码 | `lib/api/home/follow/{http,parse,export}.dart`（`followUser` / `unfollowUser`） | 同左 |

页面状态与 formhash 来源（两站一致，2026-11 实测 MT / 52pojie）：

- **资料页**（`home.php?mod=space&uid={uid}&do=profile`，PC 与移动模板结构一致）：
  `a#followmod` 的 href 即当前状态——含 `op=add&hash=…` = 未关注，含 `op=del` = 已关注。
  未关注时 `hash` 就在该链接里，直接取出即可，不必额外请求。
- **空间首页**（PC，`space-uid-*.html`）：`#unfollowflag` / `#followflag` 两个容器
  靠内联 `display:none` 互斥显示；关注/粉丝列表页则是 `a[id^=a_followmod_]`
  （`flw_btn_unfo` = 已关注）。`parseFollowState` 已兼容这三种形态。
- **已关注状态下页面不提供 hash**：此时若要再次关注，`followUser` 会在
  formhash 为空时重新拉一次资料页；若资料页仍显示已关注，直接返回成功（幂等）。
- **帖子详情页**：楼主作者区 `a[id^=followmod_{uid}]`（文案「收听TA / 不收听」），
  同样以 href 含 `op=add&hash=…` / `op=del` 判断状态；主帖卡片右上角渲染
  「关注 / 已关注」胶囊（仅主帖、非本人、非只读场景）。

响应（`inajax=1`）为 XML + CDATA，**52pojie 是 GBK**（`charset=gbk`，由 Dio 的
`responseDecoder` 统一解码）：

```html
<root><![CDATA[<div class="alert_right">成功收听
<script>…succeedhandle_followmod(…,'成功收听',
  {'fuid':'1','type':'add','special':'0','from':'list'});</script>
</div>]]></root>
```

- 成功以 `'type':'add'|'del'` 判定（文案仅用于提示）；失败为 `.alert_error` /
  `.alert_info`（如「您已收听该用户」「不能收听自己」）。
- 失败文案会原样透传给 Toast，不硬编码站点文案。

## 9. 相关文件

| 文件 | 职责 |
|---|---|
| `lib/api/forum/post/http.dart` | submitNewThread / submitReply（reppid、attachNew、seccode、secqaa）请求 |
| `lib/api/forum/post/export.dart` | submitNewPost / submitReply 汇总入口（parseSubmitResponse 解析） |
| `lib/api/forum/seccode/{http,parse,export}.dart` | 图片验证码获取、换图、JS 地址解析 |
| `lib/api/forum/secqaa/{http,parse,export}.dart` | 验证问答取题、换题、JS 题面解析 |
| `lib/core/parser/page_fetcher.dart` | 从编辑页提取 seccodehash / seccodemodid / 图片地址、secqaahash |
| `lib/pages/editor/editor_submit.dart` | submitEdit（编辑器内联实现，探针 post.edit 复用其逻辑） |
| `lib/api/home/follow/{http,parse,export}.dart` | 关注/取消关注 + 关注状态解析（资料页 `#followmod`） |
| `tool/scenarios/write_scenarios.dart` | post.new / post.reply / post.edit / post.captcha / follow.add / follow.del 探针场景 |
