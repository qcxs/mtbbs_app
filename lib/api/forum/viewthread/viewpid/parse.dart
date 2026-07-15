import 'package:html/dom.dart' as dom;

import '../../../../core/html2bbcode.dart';
import '../../../../core/page_helper.dart';
import '../../../../core/xml_helper.dart';

/// 单帖详情（viewpid）响应解析
///
/// 从 inajax XML/CDATA 中提取单条帖子/评论的完整数据。

Map<String, dynamic> parseResponse(String body, int statusCode) {
  if (statusCode != 200) {
    return {'success': false, 'message': 'HTTP $statusCode'};
  }

  final inajax = parseInajaxXml(body);
  if (inajax == null) {
    return {'success': false, 'message': '非 inajax 响应', 'raw_type': 'unknown'};
  }

  // 找帖子容器
  final postli = inajax.htmlDoc.querySelector('div.comiis_postli');
  if (postli == null) {
    return {'success': false, 'message': '未找到帖子容器'};
  }

  final post = _extractPost(postli, inajax.cdataHtml);

  return {'success': true, 'post': post, 'raw_type': 'xml_cdata'};
}

/// 从 comiis_postli 元素提取帖子所有字段
Map<String, dynamic> _extractPost(dom.Element postli, String rawHtml) {
  final pid = _extractPid(postli);
  final top = postli.querySelector('.comiis_postli_top');

  // ---- 用户信息 ----
  String nickname = '', uid = '', level = '', gender = '';
  String followUrl = '', verifyBadge = '';
  String time = '', ipLocation = '';

  if (top != null) {
    // 昵称 + UID
    final nameLink = top.querySelector('h2 a.top_user');
    if (nameLink != null) {
      nickname = sanitizeText(nameLink.text);
      final m = RegExp(
        r'space.*?uid=(\d+)',
      ).firstMatch(nameLink.attributes['href'] ?? '');
      if (m != null) uid = m.group(1)!;
    }

    // 等级
    final lev = top.querySelector('.top_lev');
    if (lev != null) level = sanitizeText(lev.text);

    // 性别
    final genderEl = top.querySelector('i.top_gender');
    if (genderEl != null) {
      final cls = genderEl.className;
      if (cls.contains('bg_boy'))
        gender = '男';
      else if (cls.contains('bg_girl'))
        gender = '女';
    }

    // 关注链接
    final followEl = top.querySelector('a.followmod, a[href*="follow&op=add"]');
    followUrl = followEl?.attributes['href'] ?? '';

    // 认证标识
    final verifyEl = top.querySelector('.comiis_verify');
    if (verifyEl != null && sanitizeText(verifyEl.text).isNotEmpty) {
      verifyBadge = sanitizeText(verifyEl.text);
    }

    // 时间（顶部区域）
    final tmEl = top.querySelector(
      '.comiis_postli_time .kmtime, .comiis_postli_time',
    );
    if (tmEl != null) {
      time = sanitizeText(tmEl.text).replaceAll(RegExp(r'\s+'), ' ').trim();
    }
  }

  // ---- 底部时间/IP（仅在 thread/detail 中有，viewpid 可能没有）----
  final bottomTime = postli.querySelector('.comiis_postli_times .comiis_tm');
  if (bottomTime != null) {
    final text = sanitizeText(
      bottomTime.text,
    ).replaceAll(RegExp(r'\s+'), ' ').trim();
    // 分离时间和IP属地
    final ipMatch = RegExp(
      r'(\d{4}[-/]\d{1,2}[-/]\d{1,2}\s*\d{1,2}:\d{2}:\d{2})\s*来自\s*(.+)$',
    ).firstMatch(text);
    if (ipMatch != null) {
      time = ipMatch.group(1)!.trim();
      ipLocation = ipMatch.group(2)!.trim();
    } else if (time.isEmpty) {
      time = text;
    }
  }

  // ---- 帖子戳记（精华等）----
  String stamp = '';
  final stampEl = postli.querySelector('.comiis_threadstamp img');
  if (stampEl != null) {
    final src = stampEl.attributes['src'] ?? '';
    if (src.contains('stamp/001.gif'))
      stamp = '精华';
    else if (src.contains('stamp/002.gif'))
      stamp = '推荐';
    else if (src.contains('stamp/003.gif'))
      stamp = '热帖';
    else
      stamp = src.split('/').last.replaceAll('.gif', '');
  }

  // ---- 帖子操作信息（精华/高亮标注）----
  String modAction = '';
  final modEl = postli.querySelector('.comiis_modact');
  if (modEl != null) {
    modAction = sanitizeText(modEl.text).replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // ---- 内容 → BBCode ----
  String bbcode = '';
  final msgEl = postli.querySelector('.comiis_messages');
  if (msgEl != null) {
    final converter = Html2BBCode();
    bbcode = converter.convertElement(msgEl);
  }

  // ---- 楼主/置顶标记 ----
  String badge = '';
  final badgeEl = postli.querySelector('h2 .top_lev.f_f, h2 .f_g');
  if (badgeEl != null) {
    badge = sanitizeText(badgeEl.text);
  }

  return {
    'pid': pid,
    'nickname': nickname,
    'uid': uid,
    'level': level,
    'gender': gender,
    'followUrl': followUrl,
    'verifyBadge': verifyBadge,
    'time': time,
    'ipLocation': ipLocation,
    'stamp': stamp,
    'modAction': modAction,
    'badge': badge,
    'bbcode': bbcode,
  };
}

/// 从 postli 元素或原始 HTML 中提取 PID
String _extractPid(dom.Element postli) {
  // 优先从 id 属性提取
  final id = postli.id;
  if (id.startsWith('pid')) return id.substring(3);
  // 其次从 a[name] 提取
  final aName = postli.querySelector('a[name^="pid"]');
  if (aName != null) {
    final name = aName.attributes['name'] ?? '';
    if (name.startsWith('pid')) return name.substring(3);
  }
  return '';
}
