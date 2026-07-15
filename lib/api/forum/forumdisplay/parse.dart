import 'dart:convert';
import 'package:html/parser.dart' as htmlParser;
import 'package:mtbbs/core/thread_parser.dart';
import 'package:mtbbs/core/page_helper.dart';
import 'package:mtbbs/core/logger.dart';

/// 版块帖子列表响应解析
///
/// 从完整 HTML 页面中提取帖子列表和分页信息。
/// 复用 thread_parser 解析帖子列表。
///
/// 返回 JSON 结构：
/// {
///   "success": true,
///   "threads": [{...}, ...],
///   "count": 50,
///   "currentPage": 1,
///   "totalPages": 9,
/// }

Map<String, dynamic> parseResponse(String body, int statusCode) {
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

  final pagination = extractPagination(doc);

  // 检查是否包含帖子列表
  if (doc.querySelector('[class*="forumlist_li"]') == null) {
    return {
      'success': true,
      'threads': <Map<String, dynamic>>[],
      'count': 0,
      'currentPage': pagination['currentPage'] ?? 1,
      'totalPages': pagination['totalPages'] ?? 1,
      'hasMore': false,
    };
  }

  final threads = parseThreadList(body);

  final cp = pagination['currentPage'] ?? 1;
  final tp = pagination['totalPages'] ?? 1;
  final hasMore = cp < tp;

  AppLogger.i(
    'PARSE',
    'forumdisplay: ${threads.length} threads (page $cp/$tp, hasMore=$hasMore)',
  );
  if (threads.isNotEmpty) {
    AppLogger.list(
      'PARSE',
      threads,
      3,
      labelFn: (t) => jsonEncode(t.toJson()),
      summary: '${threads.length} threads',
    );
  }

  return {
    'success': true,
    'threads': threads.map((t) => t.toJson()).toList(),
    'count': threads.length,
    'currentPage': cp,
    'totalPages': tp,
    'hasMore': hasMore,
  };
}
