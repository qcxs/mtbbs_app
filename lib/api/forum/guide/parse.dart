import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/core/parser/thread_parser.dart';
import 'package:mtbbs/core/app/page_helper.dart';

/// 导读响应解析
///
/// 从完整 HTML 页面中提取帖子列表和分页信息。

Map<String, dynamic> parseResponse(String body, int statusCode) {
  final pre = prepareDoc(body, statusCode);
  if (pre.error != null) return pre.error!;
  final doc = pre.doc!;

  final pagination = extractPagination(doc);

  final hasThreadList =
      doc.querySelector(
        '[class*="forumlist_li"], #threadlist, [class*="comiis_postlist"]',
      ) !=
      null;

  if (!hasThreadList) {
    return {
      'success': true,
      'threads': <Map<String, dynamic>>[],
      'count': 0,
      'currentPage': pagination['currentPage'] ?? 1,
      'totalPages': pagination['totalPages'] ?? 1,
      'hasMore': false,
      '_health': const {'parser': 'skipped', 'missing': <String>[]},
    };
  }

  final info = parseThreadListInfo(body);
  final threads = info.items;

  final cp = pagination['currentPage'] ?? 1;
  final tp = pagination['totalPages'] ?? 1;
  final hasMore = cp < tp;

  return {
    'success': true,
    'threads': threads.map((t) => t.toJson()).toList(),
    'count': threads.length,
    'currentPage': cp,
    'totalPages': tp,
    'hasMore': hasMore,
    '_health': {
      'parser': info.parser,
      // 容器存在却解析不出帖子 = 结构可能变了（区别于"确实没帖子"）。
      // 这里只告警不报错：空列表无法与"真的没帖子"区分，误报一个错误页更糟。
      'missing': (threads.isEmpty && hasThreadList)
          ? const ['列表容器存在但未解析出帖子']
          : const <String>[],
    },
  };
}
