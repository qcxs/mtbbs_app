import 'package:html/parser.dart' as htmlParser;
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
    final info = parseThreadListInfo(body);
    final threads = info.items;
    // 列表外框（表头行）在、却解析不出帖子 → 结构可能变了（只告警，不报错）
    final hasShell = htmlParser.parse(body).querySelector('table tr.th') != null;

    return {
      'success': true,
      'threads': threads.map((t) => t.toJson()).toList(),
      'count': threads.length,
      '_health': {
        'parser': info.parser,
        'missing': (threads.isEmpty && hasShell)
            ? const ['列表容器存在但未解析出帖子']
            : const <String>[],
      },
    };
  } catch (e) {
    AppLogger.e('PARSE', 'mythreads parse error: $e');
    return {'success': false, 'message': '解析失败: $e'};
  }
}
