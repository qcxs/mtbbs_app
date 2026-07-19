import '../../../core/thread_parser.dart';
import '../../../core/logger.dart';

/// 我的帖子/回复列表响应解析
///
/// 复用 thread_parser.dart 的 parseThreadList 解析 li.forumlist_li。
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
    };
  } catch (e) {
    AppLogger.e('PARSE', 'mythreads parse error: $e');
    return {'success': false, 'message': '解析失败: $e'};
  }
}
