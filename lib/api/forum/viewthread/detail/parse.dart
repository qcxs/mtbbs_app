import 'package:html/dom.dart' as dom;
import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/core/app/page_helper.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/core/parser/post_parser.dart';

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
  final pre = prepareDoc(body, statusCode);
  if (pre.error != null) return pre.error!;
  final doc = pre.doc!;

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

  // 第 1 页（无作者筛选）必然包含楼主帖：解析不到帖子 table 说明页面结构
  // 可能已变更。不能静默返回空列表——那会渲染出一个「没有内容却看似正常」的
  // 帖子，既骗过用户也骗过排查（见 docs/07 经验教训：静默失败）。
  if (postTables.isEmpty &&
      page <= 1 &&
      (authorid == null || authorid.isEmpty)) {
    AppLogger.w(
      'PARSE',
      'thread detail: tid=$tid page=$page 未解析到帖子 table（页面结构可能已变更）',
    );
    return {'success': false, 'message': '未能解析帖子内容，页面结构可能已变更'};
  }

  Map<String, dynamic>? mainPost;
  final comments = <Map<String, dynamic>>[];

  if (postTables.isEmpty) {
    // 第 2 页起 / 指定作者筛选：无帖子属正常情况
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
      '_health': const {'parser': 'discuz_table', 'missing': <String>[]},
    };
  }

  // 判断第一个帖子是否为楼主帖
  if (page > 1 || (authorid != null && authorid.isNotEmpty)) {
    // page>1 或 authorid 筛选时：全部作为评论
    for (int i = 0; i < postTables.length; i++) {
      comments.add(_parsePostSafe(postTables[i], floor: i + 1, isOp: false));
    }
  } else {
    // page=1：第一个是楼主帖
    mainPost = _parsePostSafe(postTables.first, floor: 0, isOp: true);
    mainPost['recommendUrl'] = recommendUrl;
    mainPost['favoriteUrl'] = favoriteUrl;
    mainPost['kickUrl'] = kickUrl;
    mainPost['isLiked'] = isLiked;

    for (int i = 1; i < postTables.length; i++) {
      comments.add(_parsePostSafe(postTables[i], floor: i, isOp: false));
    }
  }

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
    '_health': _healthOf(mainPost, comments),
  };
}

/// 解析单个楼层，失败时返回降级占位而不是抛异常。
///
/// 一个楼层的异常不应让整页失败——那是"雪崩"（见 docs/07 经验教训：静默失败）。
/// 降级项带 `degraded: true`，渲染层据此显示"该楼层解析失败"提示。
/// pid 用 `degraded-<floor>`：必须是**本页唯一**的值，否则渲染层按 pid 建
/// 的 GlobalKey 会重复。
Map<String, dynamic> _parsePostSafe(
  dom.Element table, {
  required int floor,
  required bool isOp,
}) {
  try {
    return parsePostFromTable(table, floor: floor, isOp: isOp);
  } catch (e) {
    AppLogger.w('PARSE', '楼层解析失败 floor=$floor: $e');
    return {
      'pid': 'degraded-$floor',
      'floor': floor,
      'floorLabel': '',
      'isOp': isOp,
      'uid': '',
      'username': '',
      'usergroup': '',
      'postTime': '',
      'ipLocation': '',
      'source': '',
      'bbcode': '',
      'followUrl': '',
      'rating': null,
      'degraded': true,
    };
  }
}

/// 解析健康自检 — 列出关键字段中的空值，供 export 层统一告警。
///
/// 目的：把「静默解析失败」变成显式信号。页面结构变化的表现通常是字段为空
/// 而不是抛异常，这里主动把它收集出来（helpers.dart 统一输出 WARN 日志）。
Map<String, dynamic> _healthOf(
  Map<String, dynamic>? mainPost,
  List<Map<String, dynamic>> comments,
) {
  final missing = <String>[];
  if (mainPost != null) {
    for (final key in const ['username', 'bbcode']) {
      if ((mainPost[key]?.toString() ?? '').isEmpty) {
        missing.add('mainPost.$key');
      }
    }
  }
  final degraded = [
    if (mainPost?['degraded'] == true) mainPost,
    ...comments.where((p) => p['degraded'] == true),
  ].length;
  if (degraded > 0) missing.add('$degraded 个楼层解析失败（已降级显示）');
  return {'parser': 'discuz_table', 'missing': missing};
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
