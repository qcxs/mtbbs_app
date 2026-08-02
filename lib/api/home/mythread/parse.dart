import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/core/parser/thread_parser.dart';

/// 我的帖子/回复列表响应解析
///
/// 复用 thread_parser.dart 的 parseThreadList 解析 li.forumlist_li。
Map<String, dynamic> parseResponse(String body, int statusCode) {
  if (statusCode != 200) {
    return {'success': false, 'message': 'HTTP $statusCode'};
  }

  try {
    final threads = parseThreadList(body);

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
