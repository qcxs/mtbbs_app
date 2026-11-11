import 'package:html/dom.dart' as dom;
import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/core/app/page_helper.dart';
import 'package:mtbbs/core/utils/uid_util.dart';

/// 关注/粉丝列表响应解析
///
/// 页面：`home.php?mod=follow&do={following|follower}[&uid={uid}][&page={page}]`
/// - following = 收听（关注）列表；follower = 听众（粉丝）列表
/// - uid 为空 = 当前登录用户自己的列表（Discuz 链接同样省略 uid）
///
/// DOM 结构（两页一致，`#ct li.cl`，均经真实页面验证）：
/// ```html
/// <li class="cl">
///   <a href="space-uid-1155.html" title="posier" class="flw_avt">
///     <img src="uc_server/avatar.php?uid=1155&size=small"></a>
///   <a id="a_followmod_1155" class="flw_btn_unfo">取消收听</a>  <!-- 粉丝页为 flw_btn_fo "收听" -->
///   <h6 class="pbn xs2">
///     <a href="space-uid-1155.html" title="posier" class="xi2">posier</a>
///     <span id="followbkame_1155" class="xg1 xs1 xw0">专做逆向教程的元老</span>  <!-- 仅自己收听页 -->
///   </h6>
///   <p><span class="xg1">最近动作: </span>【新MT管理器教程】第五课...</p>
///   <p class="ptm xg1">
///     来自: 海外  &nbsp;听众: <a href="…do=follower&uid=1155"><strong>318</strong></a>人 &nbsp;
///     收听: <a href="…do=following&uid=1155"><strong>2</strong></a>人 &nbsp;  <!-- 仅自己收听页含备注/特别收听链接 -->
///   </p>
/// </li>
/// ```
///
/// 变体差异（不影响解析）：
/// - 自己的收听页标题"我收听的人"，含 取消收听 按钮、备注、来自、修改备注/添加特别收听
/// - 自己的粉丝页标题"我的听众"，按钮为 收听
/// - 他人页标题"他收听的人/他的听众"，无备注/来自（按钮取决于当前账号与该用户的关系）
///
/// 分页复用 [extractPagination]（标准 .pg，strong 当前页 + 共 N 页 label）。
///
/// **URL 风格差异（2026-11 实测 52pojie）**：用户链接不一定是伪静态
/// `space-uid-1155.html`，也可能是查询串 `home.php?mod=space&uid=879080`
/// （MT 论坛与 52pojie 都见过后者）。只匹配 `uid-(\d+)` 会让 uid 整列为空，
/// 进而卡片点击跳到 `/user/` 这种非法路由。

Map<String, dynamic> parseResponse(String body, int statusCode) {
  final pre = prepareDoc(body, statusCode);
  if (pre.error != null) return pre.error!;
  final doc = pre.doc!;

  final items = <Map<String, dynamic>>[];
  for (final li in doc.querySelectorAll('#ct li.cl')) {
    final item = _parseItem(li);
    if (item.isNotEmpty) items.add(item);
  }

  return {
    'success': true,
    'items': items,
    'count': items.length,
    ...pagedFields(doc),
  };
}

/// 解析单个关注/粉丝 <li>（两页结构一致，兼容自己/他人变体）
Map<String, dynamic> _parseItem(dom.Element li) {
  final item = <String, dynamic>{};

  // 头像
  final avatarImg = li.querySelector('a.flw_avt img');
  if (avatarImg != null) {
    item['avatar'] = avatarImg.attributes['src'];
  }

  // 用户名 + uid（h6 内 .xi2 链接，title 优先）
  final nameLink = li.querySelector('h6 a.xi2');
  if (nameLink != null) {
    final title = sanitizeText(nameLink.attributes['title']);
    final text = sanitizeText(nameLink.text);
    final name = title.isNotEmpty ? title : text;
    if (name.isNotEmpty) item['username'] = name;
  }

  // uid：用户名链接 → 头像链接（两种模板都有）→ 列表项内第一个可识别的链接
  final uid =
      uidFromHref(nameLink?.attributes['href']) ??
      uidFromHref(li.querySelector('a.flw_avt')?.attributes['href']) ??
      _firstUidIn(li);
  if (uid != null) item['uid'] = uid;

  // 备注（仅自己的收听页有：h6 内 span[id^=followbkame_]）
  final noteEl = li.querySelector('h6 span[id^="followbkame_"]');
  if (noteEl != null) {
    final note = sanitizeText(noteEl.text);
    if (note.isNotEmpty) item['note'] = note;
  }

  // <p> 两个：无 class 的为“最近动作”，class 含 ptm 的为统计（来自/听众/收听）
  for (final p in li.querySelectorAll('p')) {
    final text = sanitizeText(p.text);
    if (p.classes.contains('ptm')) {
      // 统计：来自: X / 听众: N人 / 收听: N人
      final fromMatch = RegExp(r'来自:\s*([^\|]*?)\s*(?:听众:|$)').firstMatch(text);
      if (fromMatch != null) {
        final from = fromMatch.group(1)?.trim();
        if (from != null && from.isNotEmpty) item['from'] = from;
      }
      final follower = p.querySelector('a[href*="do=follower"] strong');
      if (follower != null) {
        item['followerCount'] = follower.text.replaceAll(RegExp(r'\D'), '');
      }
      final following = p.querySelector('a[href*="do=following"] strong');
      if (following != null) {
        item['followingCount'] = following.text.replaceAll(RegExp(r'\D'), '');
      }
    } else if (text.isNotEmpty) {
      // 最近动作：去掉前缀“最近动作: ”
      final action = text.replaceFirst(RegExp(r'^最近动作:\s*'), '').trim();
      if (action.isNotEmpty) item['recentAction'] = action;
    }
  }

  return item;
}

/// 列表项内第一个能识别出 uid 的链接（兜底，兼容非标准模板）
String? _firstUidIn(dom.Element li) {
  for (final a in li.querySelectorAll('a')) {
    final uid = uidFromHref(a.attributes['href']);
    if (uid != null) return uid;
  }
  return null;
}

// ==================== 关注 / 取消关注 ====================

/// 从用户资料页/空间页解析「当前是否已关注」「关注所需 formhash」。
///
/// 三种页面形态（2026-11 实测 MT / 52pojie）：
/// - **资料页**（`do=profile`，PC 与克米移动模板一致）：`a#followmod`
///   - 未关注：`href="…ac=follow&op=add&hash={formhash}&fuid={uid}"`
///   - 已关注：`href="…ac=follow&op=del&fuid={uid}"`（无 hash）
/// - **空间首页**（PC）：`#unfollowflag`（未关注时显示）与 `#followflag`
///   （已关注时显示）互斥，靠内联 `display:none` 区分
/// - **关注/粉丝列表**：`a[id^=a_followmod_]`，`flw_btn_unfo` 表示已关注
///
/// 返回 record：`followed` 是否已关注，`formhash` 关注时需要的哈希
/// （已关注状态下页面不提供 hash，此时为空串）。
({bool followed, String formhash}) parseFollowState(dom.Document doc) {
  final followMod = doc.querySelector('#followmod');
  if (followMod != null) {
    final href = followMod.attributes['href'] ?? '';
    final followed = href.contains('op=del');
    var hash = _hashOf(href);
    if (hash.isEmpty) hash = _formhashIn(doc);
    return (followed: followed, formhash: hash);
  }

  final followFlag = doc.querySelector('#followflag');
  final unfollowFlag = doc.querySelector('#unfollowflag');
  if (followFlag != null || unfollowFlag != null) {
    final followed = followFlag != null && _isVisible(followFlag);
    final addLink =
        doc.querySelector('#unfollowflag a[href*="op=add"]') ??
        doc.querySelector('a[href*="ac=follow"][href*="op=add"]');
    var hash = _hashOf(addLink?.attributes['href'] ?? '');
    if (hash.isEmpty) hash = _formhashIn(doc);
    return (followed: followed, formhash: hash);
  }

  final btn = doc.querySelector('a[id^="a_followmod_"]');
  if (btn != null) {
    final followed = btn.className.contains('flw_btn_unfo');
    return (followed: followed, formhash: _formhashIn(doc));
  }

  return (followed: false, formhash: _formhashIn(doc));
}

/// 从帖子页作者区的关注链接（`a[id^=followmod_{uid}]`）解析状态与 formhash。
///
/// 实测两站：未关注 `…op=add&hash={formhash}&fuid={uid}`，
/// 已关注 `…op=del&fuid={uid}`（无 hash）。链接常带域名，需自行取 query。
({bool followed, String formhash}) parseFollowHref(String href) {
  if (href.isEmpty) return (followed: false, formhash: '');
  return (followed: href.contains('op=del'), formhash: _hashOf(href));
}

/// 资料页响应 → 关注状态（供 export 在缺少 formhash 时补齐）。
Map<String, dynamic> parseFollowStateResponse(String body, int statusCode) {
  final pre = prepareDoc(body, statusCode);
  if (pre.error != null) return pre.error!;
  final state = parseFollowState(pre.doc!);
  return {
    'success': true,
    'followed': state.followed,
    'formhash': state.formhash,
  };
}

/// 解析关注/取消关注响应。
///
/// 服务端（`inajax=1`）返回 XML 包裹的提示片段，成功时形如：
/// ```html
/// <root><![CDATA[<div class="alert_right">成功收听
///   <script>…succeedhandle_followmod(…, '成功收听',
///     {'fuid':'1','type':'add','special':'0','from':'list'});</script>
/// </div>]]></root>
/// ```
/// 失败时替换为 `.alert_error` / `.alert_info`（如「您已收听该用户」「不能收听自己」）。
/// 以 `type` 是否为期望值判断成功，文案仅用于提示。
Map<String, dynamic> parseFollowResult(
  String body,
  int statusCode, {
  required bool follow,
}) {
  if (statusCode != 200) {
    return {'success': false, 'message': 'HTTP $statusCode'};
  }

  final type = RegExp(r"'type'\s*:\s*'(add|del)'").firstMatch(body)?.group(1);
  final success = type == (follow ? 'add' : 'del');

  // 提示文案：alert_right（成功）/ alert_error、alert_info（失败）
  final alert = RegExp(
    r'class="alert_(?:right|error|info)"[^>]*>([\s\S]*?)</div>',
    caseSensitive: false,
  ).firstMatch(body);
  var message = sanitizeText(
    (alert?.group(1) ?? '').replaceAll(RegExp(r'<[^>]+>'), ''),
  );
  if (message.isEmpty) {
    message = success ? (follow ? '关注成功' : '已取消关注') : '操作失败';
  }

  return {
    'success': success,
    'message': message,
    if (success) 'followed': follow,
  };
}

/// 从链接 query 中取 hash（Discuz 的 formhash 参数名在关注链接里是 `hash`）。
String _hashOf(String href) {
  if (href.isEmpty) return '';
  final m = RegExp(r'[?&](?:hash|formhash)=([0-9a-zA-Z]+)').firstMatch(href);
  return m?.group(1) ?? '';
}

/// 页面内隐藏表单的全局 formhash（移动模板资料页无此输入框）。
String _formhashIn(dom.Document doc) =>
    doc.querySelector('input[name="formhash"]')?.attributes['value'] ?? '';

/// 内联样式是否为可见（Discuz 用 `style="display: none"` 切换两个按钮容器）。
bool _isVisible(dom.Element el) {
  final style = (el.attributes['style'] ?? '').replaceAll(' ', '');
  return !style.contains('display:none');
}
