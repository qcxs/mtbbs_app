import 'package:html/dom.dart' as dom;
import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/core/parser/xml_helper.dart';
import 'package:mtbbs/core/utils/logger.dart';

/// 排行榜条目
class RankItem {
  final int rank;
  final String title;
  final String tid;
  final String threadUrl;
  final String forumName;
  final String forumUrl;
  final String author;
  final String authorUid;
  final String authorUrl;
  final String time;
  final String count;

  const RankItem({
    required this.rank,
    required this.title,
    required this.tid,
    required this.threadUrl,
    required this.forumName,
    required this.forumUrl,
    required this.author,
    required this.authorUid,
    required this.authorUrl,
    required this.time,
    required this.count,
  });

  Map<String, dynamic> toMap() => {
    'rank': rank,
    'title': title,
    'tid': tid,
    'threadUrl': threadUrl,
    'forumName': forumName,
    'forumUrl': forumUrl,
    'author': author,
    'authorUid': authorUid,
    'authorUrl': authorUrl,
    'time': time,
    'count': count,
  };
}

/// 解析帖子排行榜响应（`type=thread`）
///
/// 响应格式：XML CDATA 包裹的 HTML。
/// 支持两种模板：
///   1. 桌面 PC 模板（MT 论坛）：`<table><tr><td class="icn"><th><td class="frm"><td class="by"><td>`
///   2. 移动 App 模板（克米模板）：`<div class="comiis_postphb"><ul><li><div class="postphb_mun"><a class="postphb_tit"><p>`
Map<String, dynamic> parseThreadResponse(String body, int statusCode) {
  final pre = _prepareInajax(body, statusCode);
  if (pre.error != null) return pre.error!;
  final doc = pre.doc!;

  // 尝试两种解析策略
  var items = _parseTable(doc);
  if (items.isEmpty) {
    items = _parseLiList(doc);
  }

  return {'success': true, 'items': items.map((e) => e.toMap()).toList()};
}

/// inajax 排行榜响应统一前置：解出 XML CDATA 的 HTML 再走 [prepareDoc]。
({dom.Document? doc, Map<String, dynamic>? error}) _prepareInajax(
  String body,
  int statusCode,
) {
  if (statusCode != 200) {
    return (
      doc: null,
      error: {'success': false, 'message': 'HTTP $statusCode'},
    );
  }
  final xmlResult = parseInajaxXml(body);
  if (xmlResult == null || xmlResult.cdataHtml.isEmpty) {
    AppLogger.w('PARSE', 'ranklist: failed to parse XML CDATA');
    return (doc: null, error: {'success': false, 'message': '解析 XML 失败'});
  }
  final pre = prepareDoc(xmlResult.cdataHtml, statusCode);
  return (doc: pre.doc, error: pre.error);
}

// ==================== 策略1：桌面 PC 模板（table 结构） ====================
//
// <table>
//   <tr class="th">...</tr>  ← 跳过头行
//   <tr>
//     <td class="icn"><img src="rank_1.gif" alt="1" />或纯数字</td>
//     <th><a href="thread-xxx-1-1.html">标题</a></th>
//     <td class="frm"><a href="forum-xx-1.html">版块</a></td>
//     <td class="by"><cite><a href="space-uid-xxx.html">作者</a></cite><em>时间</em></td>
//     <td><a href="thread-xxx-1-1.html" class="xi2">数值</a></td>
//   </tr>
// </table>

List<RankItem> _parseTable(dom.Document doc) {
  final rows = doc.querySelectorAll('table tr:not(.th)');
  if (rows.isEmpty) return [];

  final items = <RankItem>[];
  for (final row in rows) {
    final th = row.querySelector('th');
    final icnTd = row.querySelector('td.icn');
    final frmTd = row.querySelector('td.frm');
    final byTd = row.querySelector('td.by');
    final allTds = row.querySelectorAll('td');
    final countTd = allTds.length >= 5 ? allTds.last : null;

    if (th == null) continue;

    // 排名
    final rank = _parseRankFromImg(icnTd);

    // 标题 + URL
    final titleLink = th.querySelector('a');
    final title = _text(titleLink);
    final threadUrl = titleLink?.attributes['href'] ?? '';
    final tid = _extractTid(threadUrl);

    // 版块
    final forumLink = frmTd?.querySelector('a');
    final forumName = _text(forumLink);
    final forumUrl = forumLink?.attributes['href'] ?? '';

    // 作者
    final citeLink = byTd?.querySelector('cite a');
    final author = _text(citeLink);
    final authorUrl = citeLink?.attributes['href'] ?? '';
    final authorUid = _extractUid(authorUrl);
    final timeEl = byTd?.querySelector('em');
    final time = _text(timeEl);

    // 统计值
    final countLink = countTd?.querySelector('a');
    final count = _text(countLink ?? countTd);

    items.add(
      RankItem(
        rank: rank,
        title: title,
        tid: tid,
        threadUrl: threadUrl,
        forumName: forumName,
        forumUrl: forumUrl,
        author: author,
        authorUid: authorUid,
        authorUrl: authorUrl,
        time: time,
        count: count,
      ),
    );
  }
  return items;
}

// ==================== 策略2：移动 App 模板（li 列表结构） ====================
//
// <div class="comiis_postphb">
//   <ul>
//     <li class="b_t">
//       <div class="postphb_mun"><img src="comiis_rank1.png" alt="1" />或纯数字</div>
//       <a href="forum.php?mod=viewthread&tid=14" class="postphb_tit">标题</a>
//       <p>
//         <span class="y f_d">8回复</span>
//         <a href="home.php?mod=space&uid=2" class="f_ok"><img src="avatar">作者</a>
//         <span class="f_d">2026-7-10 16:38</span>
//       </p>
//     </li>
//   </ul>
// </div>

List<RankItem> _parseLiList(dom.Document doc) {
  final lis = doc.querySelectorAll('.comiis_postphb li, .comiis_postphb ul li');
  if (lis.isEmpty) return [];

  final items = <RankItem>[];
  for (final li in lis) {
    // 排名
    final munDiv = li.querySelector('.postphb_mun');
    final rank = _parseRankFromImg(munDiv);

    // 标题 + URL
    final titleLink = li.querySelector('a.postphb_tit');
    final title = _text(titleLink);
    final threadUrl = titleLink?.attributes['href'] ?? '';
    final tid = _extractTid(threadUrl);

    // 作者信息（p 标签内）
    final pEl = li.querySelector('p');
    final authorLink = pEl?.querySelector('a.f_ok');
    final author = _text(authorLink);
    final authorUrl = authorLink?.attributes['href'] ?? '';
    final authorUid = _extractUid(authorUrl);

    // 时间：p 标签内最后一个 span.f_d
    final time = (() {
      final spans = pEl?.querySelectorAll('span.f_d');
      if (spans != null && spans.length >= 2) return _text(spans.last);
      return '';
    })();

    // 统计值：从 span.y f_d 中提取数字（如 "8回复"）
    final countSpan = pEl?.querySelector('span.y');
    final count = _extractCount(_text(countSpan));

    items.add(
      RankItem(
        rank: rank,
        title: title,
        tid: tid,
        threadUrl: threadUrl,
        forumName: '',
        forumUrl: '',
        author: author,
        authorUid: authorUid,
        authorUrl: authorUrl,
        time: time,
        count: count,
      ),
    );
  }
  return items;
}

// ==================== 通用工具 ====================

/// 从元素中解析排名：优先取 img.alt，否则取纯文本
int _parseRankFromImg(dom.Element? el) {
  if (el == null) return 0;
  final img = el.querySelector('img');
  if (img != null) {
    final alt = img.attributes['alt'] ?? '';
    return int.tryParse(alt) ?? 0;
  }
  return int.tryParse(el.text.trim()) ?? 0;
}

/// 从 thread URL 提取 tid
String _extractTid(String url) {
  final m = RegExp(r'thread-(\d+)').firstMatch(url);
  if (m != null) return m.group(1)!;
  final uri = Uri.tryParse(url);
  return uri?.queryParameters['tid'] ?? '';
}

/// 从 space URL 提取 uid
String _extractUid(String url) {
  final m = RegExp(r'space-uid-(\d+)').firstMatch(url);
  if (m != null) return m.group(1)!;
  final uri = Uri.tryParse(url);
  return uri?.queryParameters['uid'] ?? '';
}

/// 从 "8回复" 中提取数字
String _extractCount(String text) {
  final m = RegExp(r'(\d+)').firstMatch(text);
  return m?.group(1) ?? text;
}

String _text(dom.Element? el) => el?.text.trim() ?? '';

/// 从 forum URL 提取 fid（en/forum-50-1.html / forum.php?mod=forumdisplay&fid=50）
String _extractFid(String url) {
  final m = RegExp(r'forum-(\d+)').firstMatch(url);
  if (m != null) return m.group(1)!;
  final uri = Uri.tryParse(url);
  return uri?.queryParameters['fid'] ?? '';
}

// ==================== 用户排行（type=member） ====================
//
// PC 模板，每项一个 `<dl class="bbda cl">`：
// <dl class="bbda cl">
//   <dd class="ranknum"><img src="rank_1.gif" alt="1"></dd>   ← 前三名为图，其余纯数字
//   <dd class="m avt"><a href="space-uid-14330.html"><img src="avatar.php?uid=…"></a></dd>
//   <dt class="y">…去串个门/打招呼/发消息/加好友（无数据价值，忽略）…</dt>
//   <dt><a href="space-uid-14330.html" style="color:#FB7299;">喵喵猫</a>
//       <img src="ol.gif" alt="online"></dt>
//   <dd><p><font color="#FB7299">版主</font> 积分数: 63871人气: 23226</p></dd>
// </dl>
//
// 统计行文案随 view 变化（关键：不能写死字段）：
//   beauty/handsome → `{用户组} 积分数: N 人气: N`
//   credit          → `{用户组} 积分数: N`
//   friendnum       → `{用户组}` + 独立 `<p>好友数: N</p>`
//   invite          → `{用户组} 邀请数: <a>N</a>`
//   post            → `帖子数: <a>N</a>`（无用户组）
//   onlinetime      → `{用户组} 在线时间: N 分钟`

/// 用户排行榜条目
class MemberRankItem {
  final int rank;
  final String uid;
  final String username;
  final String avatarUrl;
  final String userGroup; // 用户组（版主/博士生…），无则空
  final String userGroupColor; // 用户组颜色（如 #FB7299），无则空
  final bool online;
  final String statLine; // 统计文案（已去掉用户组前缀），如 "积分数: 63871人气: 23226"

  const MemberRankItem({
    required this.rank,
    required this.uid,
    required this.username,
    required this.avatarUrl,
    required this.userGroup,
    required this.userGroupColor,
    required this.online,
    required this.statLine,
  });

  Map<String, dynamic> toMap() => {
    'rank': rank,
    'uid': uid,
    'username': username,
    'avatarUrl': avatarUrl,
    'userGroup': userGroup,
    'userGroupColor': userGroupColor,
    'online': online,
    'statLine': statLine,
  };
}

/// 解析用户排行榜响应（`type=member`）
Map<String, dynamic> parseMemberResponse(String body, int statusCode) {
  final pre = _prepareInajax(body, statusCode);
  if (pre.error != null) return pre.error!;
  final doc = pre.doc!;

  final items = <MemberRankItem>[];
  for (final dl in doc.querySelectorAll('dl.bbda')) {
    final item = _parseMemberDl(dl);
    if (item != null) items.add(item);
  }

  AppLogger.i('PARSE', 'member ranklist: ${items.length} items');
  return {'success': true, 'items': items.map((e) => e.toMap()).toList()};
}

MemberRankItem? _parseMemberDl(dom.Element dl) {
  // 排名
  final rank = _parseRankFromImg(dl.querySelector('dd.ranknum'));

  // 头像
  final avatarUrl =
      dl.querySelector('dd.avt img, dd.m img')?.attributes['src'] ?? '';

  // 用户名 / uid / 在线状态：取非 `.y`（那是操作链接）的 dt
  dom.Element? nameDt;
  for (final dt in dl.querySelectorAll('dt')) {
    if (!dt.classes.contains('y')) {
      nameDt = dt;
      break;
    }
  }
  final nameLink = nameDt?.querySelector('a[href*=space-uid-]');
  final username = _text(nameLink);
  final uid = _extractUid(nameLink?.attributes['href'] ?? '');
  final online = nameDt?.querySelector('img[alt=online]') != null;

  // 统计行：最后一个 dd 内所有 <p> 的文本（friendnum 会拆成两个 <p>）
  final dds = dl.querySelectorAll('dd');
  final statDd = dds.length >= 3 ? dds.last : null;
  final fullStats = (statDd?.querySelectorAll('p') ?? const <dom.Element>[])
      .map((p) => _text(p))
      .where((t) => t.isNotEmpty)
      .join(' ');

  // 用户组：优先 <font>（有色用户组）；否则取首段"非标签/非数值"文本（如 onlinetime 的"博士后"）
  final font = statDd?.querySelector('font');
  var userGroup = _text(font);
  final userGroupColor = font?.attributes['color']?.trim() ?? '';
  if (userGroup.isEmpty && fullStats.isNotEmpty) {
    final first = fullStats.split(RegExp(r'\s+')).first;
    if (!first.contains(':') && !RegExp(r'\d').hasMatch(first)) {
      userGroup = first;
    }
  }

  // 统计文案：去掉开头的用户组，避免与用户名行的用户组标签重复
  var statLine = fullStats;
  if (userGroup.isNotEmpty && statLine.startsWith(userGroup)) {
    statLine = statLine.substring(userGroup.length).trim();
  }

  if (uid.isEmpty && username.isEmpty) return null;

  return MemberRankItem(
    rank: rank,
    uid: uid,
    username: username,
    avatarUrl: avatarUrl,
    userGroup: userGroup,
    userGroupColor: userGroupColor,
    online: online,
    statLine: statLine,
  );
}

// ==================== 版块排行（type=forum） ====================
//
// PC 模板，每项一个 <tr>（表头行的 th 内无 <a>，据此过滤）：
// <tr>
//   <td class="icn" height="36"><img src="rank_1.gif" alt="1"></td>
//   <th><a href="forum-50-1.html">休闲灌水</a></th>
//   <td>31986</td>
// </tr>

/// 版块排行榜条目
class ForumRankItem {
  final int rank;
  final String fid;
  final String forumName;
  final String forumUrl;
  final String count;

  const ForumRankItem({
    required this.rank,
    required this.fid,
    required this.forumName,
    required this.forumUrl,
    required this.count,
  });

  Map<String, dynamic> toMap() => {
    'rank': rank,
    'fid': fid,
    'forumName': forumName,
    'forumUrl': forumUrl,
    'count': count,
  };
}

/// 解析版块排行榜响应（`type=forum`）
Map<String, dynamic> parseForumResponse(String body, int statusCode) {
  final pre = _prepareInajax(body, statusCode);
  if (pre.error != null) return pre.error!;
  final doc = pre.doc!;

  final items = <ForumRankItem>[];
  for (final row in doc.querySelectorAll('table tr')) {
    final link = row.querySelector('th a');
    if (link == null) continue; // 跳过表头行 / 空行
    final forumUrl = link.attributes['href'] ?? '';
    final tds = row.querySelectorAll('td');
    items.add(
      ForumRankItem(
        rank: _parseRankFromImg(row.querySelector('td.icn')),
        fid: _extractFid(forumUrl),
        forumName: _text(link),
        forumUrl: forumUrl,
        count: tds.isEmpty ? '' : _text(tds.last),
      ),
    );
  }

  AppLogger.i('PARSE', 'forum ranklist: ${items.length} items');
  return {'success': true, 'items': items.map((e) => e.toMap()).toList()};
}
