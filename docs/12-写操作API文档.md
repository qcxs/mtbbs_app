# 12-写操作 API 文档（发帖/评论/回复/修改）

> 适用：发帖/评论/回复/修改四种写操作（formhash/posttime/Content-Type 协议）。按需。

> 来源：测试站 discuz.qcxs.top 实测（2026-08-02，账号 user1）。
> 探针场景：`post.new` / `post.reply`（含 reppid）/ `post.edit`，见 `tool/api_scenarios.dart`。

## 0. 核心机制（四种操作通用）

| 字段 | 说明 |
|---|---|
| `formhash` | Discuz CSRF 令牌，**必填**。来自页面隐藏 `<input name="formhash">`，每次会话不同 |
| `posttime` | 时间戳，来自页面隐藏 `<input name="posttime">` |
| `inajax=1` | 提交 URL 参数，Discuz 返回 inajax 格式响应（XML/文本） |
| `Content-Type` | **必须显式** `application/x-www-form-urlencoded`（Dio 对 Map 不自动加头，否则 Discuz 收不到 `$_POST` 报"表单验证串不符"） |

**fid 规则**：只有发帖需要真实 fid；评论/回复/修改由 tid 推导（URL 里 `fid=` 空值与无 fid 效果相同，服务端忽略）。

**通用流程**（两步）：
1. GET 对应页面 → 提取 `formhash`/`posttime`（及 fid）
2. POST 提交端点 + form-urlencoded 表单

## 1. 发帖 — fid

| 项 | 值 |
|---|---|
| 加载页 | `GET /forum.php?mod=post&action=newthread&fid={fid}` |
| 提交端点 | `POST /forum.php?mod=post&action=newthread&fid={fid}&topicsubmit=yes&inajax=1` |
| 必填参数 | `formhash` `posttime` `topicsubmit=yes` `subject`(标题) `message`(内容) |
| 探针场景 | `post.new`（fid、subject、message 必填） |

成功响应：`非常感谢，您的主题已发布…`，返回新 `tid`。

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
- **实时轮询**：Discuz **没有**"增量拉新消息"接口（`op=checknewpm` 只更新 `newpm` 状态位，不返回内容），客户端只能周期重拉最新一页、按 `pmid` 去重后追加（`PmChatPage` 每 5s 一次，前台+页面可见时才跑）。
- **已读**：加载会话页本身就会清除该会话的未读标记（实测 `message.pm` 的 `isNew` 由 `true` → `false`），无需额外的"标记已读"请求。

## 7. 相关文件

| 文件 | 职责 |
|---|---|
| `lib/api/forum/post/http.dart` | submitNewThread / submitReply（reppid、attachNew）请求 |
| `lib/api/forum/post/export.dart` | submitNewPost / submitReply 汇总入口（parseSubmitResponse 解析） |
| `lib/pages/editor/editor_submit.dart` | submitEdit（编辑器内联实现，探针 post.edit 复用其逻辑） |
| `tool/api_scenarios.dart` | post.new / post.reply / post.edit 探针场景 |
