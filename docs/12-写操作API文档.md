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

## 6. 相关文件

| 文件 | 职责 |
|---|---|
| `lib/api/forum/post/http.dart` | submitNewThread / submitReply（reppid、attachNew）请求 |
| `lib/api/forum/post/export.dart` | submitNewPost / submitReply 汇总入口（parseSubmitResponse 解析） |
| `lib/pages/editor/editor_submit.dart` | submitEdit（编辑器内联实现，探针 post.edit 复用其逻辑） |
| `tool/api_scenarios.dart` | post.new / post.reply / post.edit 探针场景 |
