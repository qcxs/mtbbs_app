import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:mtbbs/core/app/page_helper.dart';

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

Map<String, dynamic> parseResponse(String body, int statusCode) {
  if (statusCode != 200) {
    return {'success': false, 'message': 'HTTP $statusCode'};
  }

  final doc = html_parser.parse(body);

  // 统一检测 Discuz 错误页/登录页
  final pageError = checkPageError(doc, body);
  if (pageError.isError) {
    return {
      'success': false,
      'message': pageError.message ?? '页面错误',
      'loginRequired': pageError.loginRequired,
    };
  }

  final items = <Map<String, dynamic>>[];
  for (final li in doc.querySelectorAll('#ct li.cl')) {
    final item = _parseItem(li);
    if (item.isNotEmpty) items.add(item);
  }

  final pagination = extractPagination(doc);
  final currentPage = pagination['currentPage'] ?? 1;
  final totalPages = pagination['totalPages'] ?? 1;

  return {
    'success': true,
    'items': items,
    'count': items.length,
    'currentPage': currentPage,
    'totalPages': totalPages,
    'hasMore': currentPage < totalPages,
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

    final m = RegExp(
      r'uid-(\d+)',
    ).firstMatch(nameLink.attributes['href'] ?? '');
    if (m != null) item['uid'] = m.group(1);
  }

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
