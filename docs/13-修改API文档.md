# 13-修改 API 文档（帖子/评论）

> 适用：修改帖子/评论（action=edit 协议、成功判定、踩坑）。按需。

> 一句话机制：**Discuz 帖子和评论存同一张表，楼主帖 = pid 第一个**，所以改帖子与改评论都走 `action=edit` + `tid` + `pid`，仅 pid 不同。

## 1. 探针命令（直接可复制）

```bash
# 修改评论（tid + pid = 楼层 pid）
flutter test tool/api_probe_test.dart --dart-define=cmd=post.edit --dart-define=tid=18 --dart-define=pid=62 --dart-define=message=新内容 --dart-define=account=user1 --dart-define=baseUrl=http://discuz.qcxs.top

# 修改楼主帖（pid = 楼主的 pid，即帖子本体；可带 subject 改标题）
flutter test tool/api_probe_test.dart --dart-define=cmd=post.edit --dart-define=tid=18 --dart-define=pid=55 --dart-define=subject=新标题 --dart-define=message=新内容 --dart-define=account=user1 --dart-define=baseUrl=http://discuz.qcxs.top
```

## 2. 请求协议

| 步骤 | 说明 |
|---|---|
| GET | `/forum.php?mod=post&action=edit&fid={fid}&tid={tid}&pid={pid}` → 提取 `formhash`/`posttime`（fid 可空，由 tid 推导） |
| POST | 同 URL + `&editsubmit=yes&inajax=1&formhash={formhash}`，form 含 `formhash` `posttime` `subject` `message` `fid` `tid` `pid` `page=1` `editsubmit=yes` |

**Content-Type 必须显式** `application/x-www-form-urlencoded`（Dio 对 Map 不自动加头）。

## 3. 成功判定

| 情况 | 判定 |
|---|---|
| 修改成功 | 返回 **301/302**，`Location` 含 `viewthread` |
| 失败 | 正文含 `抱歉/无权/权限/不能/非法` 等关键词 |
| 审核 | 正文含 `审核` → `needsApproval=true` |

## 4. 踩坑清单（全部实测踩过）

1. **`pid` 是必填且不在探针 args 白名单** → 必报"缺少必填参数: pid"。新参数键必须加进 `api_probe_test.dart` 的 args map（逐键 const 读取）。
2. **Dio 默认把 301/302 当异常抛** → POST 必须 `followRedirects: false` + `validateStatus: (s) => s != null && s < 500`，由 parse 层按 Location 判定。
3. **fid 不需要**：修改由 tid 推导 fid，`fid=` 空值与无 fid 效果相同（测试站/MT 论坛均验证）。
4. **拿 pid 的方式**：`thread.detail`（探针）返回楼层 pid，或 Chrome 帖子页 `#post_{pid}`。

## 5. 可重复验证步骤

1. `thread.detail tid=X` 拿到目标楼层 pid（或 Chrome 看 `#post_{pid}`）
2. `post.edit tid=X pid=Y message=测试` → 期待 `success:true`
3. Chrome 打开帖子页刷新 → 楼层内容更新且带"本帖最后由…编辑"标记
4. 反向验证：传不存在的 pid → 期待报错（"帖子不存在/无权"）确认错误分支也正常

## 6. 相关文件

| 文件 | 职责 |
|---|---|
| `lib/pages/editor/editor_submit.dart` | App 内 submitEdit（探针 post.edit 复刻其协议） |
| `tool/scenarios/write_scenarios.dart` | post.edit 探针场景 |
| `docs/12-写操作API文档.md` | 四种写操作总览（发帖/评论/回复/修改） |
