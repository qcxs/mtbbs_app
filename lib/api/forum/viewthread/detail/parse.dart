import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as htmlParser;
import 'package:mtbbs/core/page_helper.dart';
import 'package:mtbbs/core/logger.dart';
import 'package:mtbbs/core/post_parser.dart';

/// 帖子详情响应解析（PC 模板）
///
/// 兼容两种模板结构：
/// - 标准 Discuz：`#postlist > table#pidXX.plhin`
/// - 克米模板：   `#postlist > div.comiis_vrx > table#pidXX.plhin`
///
/// 解析器统一从 `table#pidXX.plhin` 出发，内部 TD.pls（作者）和 TD.plc（内容）结构一致。
/// 单帖提取委托给 [parsePostFromTable]（见 lib/core/post_parser.dart）。

Map<String, dynamic> parseResponse(
  String body,
  int statusCode, {
  int page = 1,
  String? authorid,
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
  final recommendUrl = resolveUrl(_extractRecommendUrl(doc));
  final favoriteUrl = resolveUrl(_extractFavoriteUrl(doc));
  final kickUrl = resolveUrl(_extractKickUrl(doc));
  final isLiked =
      doc.querySelector(
        'a[href*="recommend"][href*="do=add"].recommend_ok, '
        'a.recommend_ok, [class*="recommend_ok"]',
      ) !=
      null;

  // 提取所有帖子 table
  // 标准 Discuz：直接 table
  // 克米模板：   .comiis_vrx > table
  // div[id^="post_"] 包装：标准 Discuz 变体
  var postTables = doc
      .querySelectorAll('#postlist > table[id^="pid"]')
      .toList();
  if (postTables.isEmpty) {
    postTables = doc
        .querySelectorAll('#postlist .comiis_vrx > table[id^="pid"]')
        .toList();
  }
  if (postTables.isEmpty) {
    postTables = doc
        .querySelectorAll('#postlist div[id^="post_"] > table[id^="pid"]')
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
  if (page > 1 || (authorid != null && authorid.isNotEmpty)) {
    // page>1 或 authorid 筛选时：全部作为评论
    for (int i = 0; i < postTables.length; i++) {
      comments.add(
        parsePostFromTable(postTables[i], floor: i + 1, isOp: false),
      );
    }
  } else {
    // page=1：第一个是楼主帖
    mainPost = parsePostFromTable(postTables.first, floor: 0, isOp: true);
    mainPost['recommendUrl'] = recommendUrl;
    mainPost['favoriteUrl'] = favoriteUrl;
    mainPost['kickUrl'] = kickUrl;
    mainPost['isLiked'] = isLiked;

    for (int i = 1; i < postTables.length; i++) {
      comments.add(parsePostFromTable(postTables[i], floor: i, isOp: false));
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
