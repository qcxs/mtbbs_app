import '../../../core/thread_parser.dart';
import '../../../core/logger.dart';

/// 我的帖子/回复列表响应解析
///
/// 复用 thread_parser.dart 的 parseThreadList 解析 li.forumlist_li。
/// 分页判断：能提取出帖子说明还有更多，直到 loadMore 返回空为止。
/// 页面上没有总页数信息，只有上一页/下一页链接，所以由调用端自主判断。
Map<String, dynamic> parseResponse(String body, int statusCode) {
  if (statusCode != 200) {
    return {'success': false, 'message': 'HTTP $statusCode'};
  }

  try {
    final threads = parseThreadList(body);

    AppLogger.i('PARSE', 'mythreads: ${threads.length} items');
    if (threads.isNotEmpty && threads.length <= 3) {
      for (final t in threads) {
        AppLogger.d('PARSE', '  ${t.title}(${t.threadId})');
      }
    }

    return {
      'success': true,
      'threads': threads.map((t) => t.toJson()).toList(),
      'count': threads.length,
      // 能提取到帖子说明可能还有更多，由 loadMore 判断是否到底
      'hasMore': threads.isNotEmpty,
    };
  } catch (e) {
    AppLogger.e('PARSE', 'mythreads parse error: $e');
    return {'success': false, 'message': '解析失败: $e'};
  }
}
