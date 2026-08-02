import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:mtbbs/core/app/page_helper.dart';
import 'package:mtbbs/core/utils/logger.dart';

/// 好友列表响应解析
///
/// 页面：`home.php?mod=space&uid={uid}&do=friend&from=space&page={page}`
///
/// DOM 结构有两种变体：
/// ```html
/// <!-- 查看他人好友页（<li class="bbda cl">） -->
/// <li class="bbda cl">
///   <div class="avt"><a href="space-uid-102514.html"><img src="avatar?uid=102514"></a></div>
///   <h4><a href="space-uid-102514.html" title="choukongbai">choukongbai</a></h4>
///   <p class="maxh">小学生 &nbsp;积分数: 184</p>
///   <div class="xg1">…互动区，跳过…</div>
/// </li>
///
/// <!-- 自己的好友页（<li id="friend_139510_li">，h4 内“热度”链接在前，p.maxh 是好友备注） -->
/// <li id="friend_139510_li">
///   <div class="avt"><a href="space-uid-139510.html"><img src="avatar?uid=139510"></a></div>
///   <h4>
///     <span class="xg1 xw0 y"><a href="…spacecp…&uid=139510…" title="热度">热度(37)</a></span>
///     <a href="space-uid-139510.html">笑</a>
///   </h4>
///   <p class="maxh">OMG你吓到我啦~</p>
/// </li>
/// ```
///
/// 权限受限（他人隐私设置）：`#ct > .nfl > h2.xs2` 提示"不能访问"，
/// 此时无 `.buddy` 列表，返回 `privacyBlocked: true`。
///
/// 分页复用 [extractPagination]（.pg 分页栏）。

Map<String, dynamic> parseResponse(String body, int statusCode) {
  if (statusCode != 200) {
    return {'success': false, 'message': 'HTTP $statusCode'};
  }

  final doc = html_parser.parse(body);

  // 统一检测 Discuz 错误页
  final pageError = checkPageError(doc, body);
  if (pageError.isError) {
    return {
      'success': false,
      'message': pageError.message ?? '页面错误',
      'loginRequired': pageError.loginRequired,
    };
  }

  // 隐私设置：无权查看该用户的好友列表
  final privacy = doc.querySelector('.nfl h2');
  if (privacy != null) {
    final text = sanitizeText(privacy.text);
    if (text.contains('隐私设置') || text.contains('不能访问')) {
      AppLogger.w('PARSE', 'friend: privacy blocked: $text');
      return {'success': false, 'privacyBlocked': true, 'message': text};
    }
  }

  final friends = <Map<String, dynamic>>[];
  for (final li in doc.querySelectorAll('ul.buddy.cl > li')) {
    final friend = _parseFriend(li);
    if (friend.isNotEmpty) friends.add(friend);
  }

  final pagination = extractPagination(doc);
  final currentPage = pagination['currentPage'] ?? 1;
  final totalPages = pagination['totalPages'] ?? 1;

  return {
    'success': true,
    'items': friends,
    'count': friends.length,
    'currentPage': currentPage,
    'totalPages': totalPages,
    'hasMore': currentPage < totalPages,
  };
}

/// 解析单个好友 <li>（兼容查看他人 / 自己的两种 DOM 变体）
Map<String, dynamic> _parseFriend(dom.Element li) {
  final friend = <String, dynamic>{};

  // 头像
  final avatarImg = li.querySelector('.avt img');
  if (avatarImg != null) {
    friend['avatar'] = avatarImg.attributes['src'];
  }

  // 用户名 + uid
  // 注意：自己页 h4 内第一个 <a> 是“热度”链接（href 为 spacecp，非 space-uid），
  // 必须过滤，只取 href 含 space-uid- 的用户名链接。
  final anchors = li.querySelectorAll('h4 a');
  dom.Element? nameLink;
  for (final a in anchors) {
    if ((a.attributes['href'] ?? '').contains('space-uid-')) {
      nameLink = a;
      break;
    }
  }
  nameLink ??= anchors.isNotEmpty ? anchors.first : null;
  if (nameLink != null) {
    final title = sanitizeText(nameLink.attributes['title']);
    final text = sanitizeText(nameLink.text);
    final name = title.isNotEmpty ? title : text;
    if (name.isNotEmpty) friend['username'] = name;

    final href = nameLink.attributes['href'] ?? '';
    final m = RegExp(r'uid-(\d+)').firstMatch(href);
    if (m != null) friend['uid'] = m.group(1);
  }

  // 用户组 + 积分 / 好友备注（<p class="maxh">）
  // - 他人页：`小学生 积分数: 184`（用户组 + 积分）
  // - 自己页：`OMG你吓到我啦~`（好友备注，无“积分数”格式）
  final groupP = li.querySelector('p.maxh');
  if (groupP != null) {
    final text = sanitizeText(groupP.text);
    final gm = RegExp(r'^(.+?)\s+积分数:\s*([\d,]+)').firstMatch(text);
    if (gm != null) {
      final group = gm.group(1)?.trim();
      if (group != null && group.isNotEmpty) friend['userGroup'] = group;
      friend['credits'] = gm.group(2)?.replaceAll(',', '');
    } else if (text.isNotEmpty) {
      friend['note'] = text;
    }
  }

  // 热度（仅自己的好友页有：h4 内 热度(N) 链接）
  final hotLink = li.querySelector('h4 a[title="热度"]');
  if (hotLink != null) {
    final m = RegExp(r'热度\((\d+)\)').firstMatch(sanitizeText(hotLink.text));
    if (m != null) friend['hot'] = m.group(1);
  }

  return friend;
}
