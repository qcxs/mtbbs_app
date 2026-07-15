import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as htmlParser;
import 'package:mtbbs/core/html2bbcode.dart';
import 'package:mtbbs/core/page_helper.dart';
import 'package:mtbbs/core/logger.dart';
import 'package:mtbbs/config/site_config.dart';

/// 帖子详情响应解析（PC 模板）
///
/// 兼容两种模板结构：
/// - 标准 Discuz：`#postlist > table#pidXX.plhin`
/// - 克米模板：   `#postlist > div.comiis_vrx > table#pidXX.plhin`
///
/// 解析器统一从 `table#pidXX.plhin` 出发，内部 TD.pls（作者）和 TD.plc（内容）结构一致。
/// 仅包含两个站点共有的公共字段，站点特有字段（如勋章、评分列表）不解析。

/// 将相对 URL 解析为绝对 URL
String _resolveUrl(String href) {
  if (href.isEmpty) return '';
  final uri = Uri.tryParse(href);
  if (uri == null) return href;
  if (uri.hasScheme) return href;
  final base = Uri.parse(SiteConfig.baseUrl);
  return base.resolve(href).toString();
}

Map<String, dynamic> parseResponse(
  String body,
  int statusCode, {
  int page = 1,
}) {
  if (statusCode != 200) {
    return {'success': false, 'message': 'HTTP $statusCode'};
  }

  final doc = htmlParser.parse(body);

  // 统一检测 Discuz 错误页
  final pageError = checkPageError(doc, body);
  if (pageError.isError) {
    return {
      'success': false,
      'message': pageError.message ?? '页面错误',
      'loginRequired': pageError.loginRequired,
    };
  }

  final tid = _extractTid(doc);
  final title = _extractTitle(doc);
  final pagination = extractPagination(doc);
  final currentPage = pagination['currentPage'] as int;
  final totalPages = pagination['totalPages'] as int;

  // formhash
  final formhash = _extractFormhash(doc);

  // 全局操作 URL
  final recommendUrl = _resolveUrl(_extractRecommendUrl(doc));
  final favoriteUrl = _resolveUrl(_extractFavoriteUrl(doc));
  final kickUrl = _resolveUrl(_extractKickUrl(doc));
  final isLiked =
      doc.querySelector(
        'a[href*="recommend"][href*="do=add"].recommend_ok, '
        'a.recommend_ok, [class*="recommend_ok"]',
      ) !=
      null;

  // 提取所有帖子 table
  // 标准 Discuz：直接 table
  // 克米模板：   .comiis_vrx > table
  var postTables = doc
      .querySelectorAll('#postlist > table[id^="pid"]')
      .toList();
  if (postTables.isEmpty) {
    postTables = doc
        .querySelectorAll('#postlist .comiis_vrx > table[id^="pid"]')
        .toList();
  }

  // 必要内容校验
  if (postTables.isEmpty && tid.isEmpty) {
    AppLogger.w('PARSE', 'thread detail: no posts and no tid');
    return {'success': false, 'message': '页面格式异常'};
  }

  Map<String, dynamic>? mainPost;
  final comments = <Map<String, dynamic>>[];

  if (postTables.isEmpty) {
    AppLogger.i('PARSE', 'thread detail: empty (tid=$tid, title="$title")');
    return {
      'success': true,
      'tid': tid,
      'title': title,
      'formhash': formhash,
      'currentPage': currentPage,
      'totalPages': totalPages,
      'mainPost': null,
      'posts': <Map<String, dynamic>>[],
      'count': 0,
      'recommendUrl': recommendUrl,
      'favoriteUrl': favoriteUrl,
      'kickUrl': kickUrl,
      'isLiked': isLiked,
    };
  }

  // 判断第一个帖子是否为楼主帖
  if (page > 1) {
    // page>1：全部作为评论
    for (int i = 0; i < postTables.length; i++) {
      comments.add(_extractPost(postTables[i], floor: i + 1, isOp: false));
    }
  } else {
    // page=1：第一个是楼主帖
    mainPost = _extractPost(postTables.first, floor: 0, isOp: true);
    mainPost['recommendUrl'] = recommendUrl;
    mainPost['favoriteUrl'] = favoriteUrl;
    mainPost['kickUrl'] = kickUrl;
    mainPost['isLiked'] = isLiked;

    for (int i = 1; i < postTables.length; i++) {
      comments.add(_extractPost(postTables[i], floor: i, isOp: false));
    }
  }

  AppLogger.i(
    'PARSE',
    jsonEncode({
      'type': 'thread_detail',
      'title': title,
      'comments': comments.length,
      'page': currentPage,
      'totalPages': totalPages,
      'tid': tid,
    }),
  );

  return {
    'success': true,
    'tid': tid,
    'title': title,
    'formhash': formhash,
    'currentPage': currentPage,
    'totalPages': totalPages,
    'mainPost': mainPost,
    'posts': comments,
    'count': comments.length,
    'recommendUrl': recommendUrl,
    'favoriteUrl': favoriteUrl,
    'kickUrl': kickUrl,
    'isLiked': isLiked,
  };
}

// ============================================================
// formhash 提取
// ============================================================

String _extractFormhash(dom.Document doc) {
  final input = doc.querySelector('input[name="formhash"]');
  return input?.attributes['value'] ?? '';
}

// ============================================================
// 全局操作 URL 提取
// ============================================================

String _extractRecommendUrl(dom.Document doc) {
  final a = doc.querySelector('a[href*="recommend"][href*="do=add"]');
  return a?.attributes['href'] ?? '';
}

String _extractFavoriteUrl(dom.Document doc) {
  final a = doc.querySelector(
    'a[href*="favorite"][href*="handlekey=favorite"]',
  );
  return a?.attributes['href'] ?? '';
}

String _extractKickUrl(dom.Document doc) {
  // 标准 Discuz：a#postreport
  // 克米模板：   a[href*="action=report"]
  final a = doc.querySelector('a#postreport, a[href*="action=report"]');
  return a?.attributes['href'] ?? '';
}

// ============================================================
// TID 提取
// ============================================================

String _extractTid(dom.Document doc) {
  for (final a in doc.querySelectorAll(
    'a[href*="tid="], a[href*="viewthread"]',
  )) {
    final href = a.attributes['href'] ?? '';
    final m = RegExp(r'tid=(\d+)').firstMatch(href);
    if (m != null) return m.group(1)!;
  }
  return '';
}

// ============================================================
// 标题提取
// ============================================================

String _extractTitle(dom.Document doc) {
  final subject = doc.querySelector('#thread_subject');
  if (subject != null) {
    return sanitizeText(subject.text);
  }
  return '';
}

// ============================================================
// 单帖提取
// ============================================================

/// 从 table#pidXX 元素提取帖子数据
Map<String, dynamic> _extractPost(
  dom.Element table, {
  bool isOp = false,
  int floor = 0,
}) {
  final converter = Html2BBCode();

  // ---- PID ----
  final pid = _extractPid(table);

  // ---- 作者信息区 TD.pls ----
  final pls = table.querySelector('td.pls');

  String uid = '', username = '', usergroup = '', followUrl = '';

  if (pls != null) {
    // 昵称 + UID
    final nameLink = pls.querySelector('.pi .authi a');
    if (nameLink != null) {
      username = sanitizeText(nameLink.text);
      final href = nameLink.attributes['href'] ?? '';
      final m = RegExp(r'space.*?uid[=-](\d+)').firstMatch(href);
      if (m != null) uid = m.group(1)!;
    }

    // 用户组
    final lev = pls.querySelector('p em a');
    if (lev != null) usergroup = sanitizeText(lev.text);

    // 关注链接
    final followEl = pls.querySelector('a[id^="followmod_"]');
    followUrl = _resolveUrl(followEl?.attributes['href'] ?? '');
  }

  // ---- 帖子内容区 TD.plc ----
  final plc = table.querySelector('td.plc');

  String floorLabel = '',
      postTime = '',
      ipLocation = '',
      source = '',
      bbcode = '',
      rateUrl = '';

  if (plc != null) {
    // 楼层标签
    final postnum = plc.querySelector('a[id^="postnum"]');
    if (postnum != null) {
      floorLabel = sanitizeText(
        postnum.text,
      ).replaceAll(RegExp(r'\s+'), ' ').trim();
      // 提取楼层数字
      final floorMatch = RegExp(r'#(\d+)').firstMatch(floorLabel);
      if (floorMatch != null) {
        floor = int.tryParse(floorMatch.group(1)!) ?? floor;
      }
    }

    // 帖子头部信息
    final authi = plc.querySelector('.pti .authi');
    if (authi != null) {
      // 发布时间
      final tmEl = authi.querySelector('em[id^="authorposton"]');
      if (tmEl != null) {
        postTime = sanitizeText(tmEl.text)
            .replaceAll(RegExp(r'发表于\s*'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
      }

      // 来源（"来自手机"等）
      final srcEl = authi.querySelector('.xg1');
      if (srcEl != null) {
        source = sanitizeText(srcEl.text).trim();
      }

      // IP 属地（克米模板特有，标准 Discuz 无此元素）
      final ipEl = authi.querySelector('code.comiis_iplocality');
      if (ipEl != null) {
        ipLocation = sanitizeText(ipEl.text)
            .replaceAll(RegExp(r'来自\s*'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
      }
    }

    // 帖子正文 → BBCode
    final msgEl = plc.querySelector('td.t_f[id^="postmessage_"]');
    if (msgEl != null) {
      bbcode = converter.convertElementContent(msgEl);
    }

    // 评分 URL
    final rateLink = plc.querySelector('.po .pob.cl a[onclick*="action=rate"]');
    if (rateLink != null) {
      final onclick = rateLink.attributes['onclick'] ?? '';
      final m = RegExp(r"'(/[^']+)'").firstMatch(onclick);
      if (m != null) {
        rateUrl = _resolveUrl(m.group(1)!);
      }
    }
  }

  return {
    'pid': pid,
    'floor': floor,
    'floorLabel': floorLabel,
    'isOp': isOp,
    'uid': uid,
    'username': username,
    'usergroup': usergroup,
    'postTime': postTime,
    'ipLocation': ipLocation,
    'source': source,
    'bbcode': bbcode,
    'rateUrl': rateUrl,
    'followUrl': followUrl,
  };
}

/// 从 table#pidXX 提取 PID
String _extractPid(dom.Element table) {
  final id = table.id;
  if (id.startsWith('pid')) return id.substring(3);
  return '';
}
