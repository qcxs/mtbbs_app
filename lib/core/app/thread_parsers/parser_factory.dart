import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as htmlParser;
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/models/thread_item.dart';
import 'thread_list_parser.dart';
import 'comiis_card_parser.dart';
import 'discuz_table_parser.dart';
import 'comiis_table_parser.dart';
import 'space_thread_parser.dart';

/// 帖子列表解析结果
///
/// [parser] 为 `'NoParser'` 表示没有任何解析器匹配当前页面结构
/// （可能是版块确实为空，也可能是模板结构变了——见 [matched]）。
class ThreadListParseResult {
  final String parser;
  final List<ThreadItem> items;

  const ThreadListParseResult({required this.parser, required this.items});

  /// 是否有解析器命中了页面结构
  bool get matched => parser != 'NoParser';
}

/// 帖子列表解析器工厂
///
/// 通过特征识别自动选择合适的解析器，支持扩展：
/// 新增模板只需实现 [ThreadListParser] 接口并注册到 [_parsers] 列表。
class ThreadListParserFactory {
  static final List<ThreadListParser> _parsers = [
    // 顺序：comiis_card → discuz_table → comiis_table → space_thread
    ComiisCardParser(),
    DiscuzTableParser(),
    ComiisTableParser(),
    SpaceThreadParser(),
  ];

  /// 注册自定义解析器（添加到队首，优先级最高）
  static void register(ThreadListParser parser) {
    _parsers.insert(0, parser);
  }

  /// 自动检测并解析帖子列表 HTML，并返回命中的解析器名（供健康自检/告警用）。
  ///
  /// 注意：[ThreadListParser.canParse] 是**条目级**判据（要找到帖子元素才算命中），
  /// 因此 `matched == false` 既可能是"版块确实没有帖子"，也可能是"模板结构变了"，
  /// 调用方不要据此直接判定失败，只做告警。
  static ThreadListParseResult parseWithInfo(String html) {
    final doc = _parseDoc(html);
    for (final parser in _parsers) {
      if (parser.canParse(doc)) {
        final items = parser.parse(doc);
        final name = parser.runtimeType.toString();
        AppLogger.d('PARSE', 'thread list ← $name (${items.length} items)');
        return ThreadListParseResult(parser: name, items: items);
      }
    }
    AppLogger.w('PARSE', 'thread list: 无解析器匹配当前页面结构');
    return const ThreadListParseResult(parser: 'NoParser', items: []);
  }

  /// 自动检测并解析帖子列表 HTML
  static List<ThreadItem> parse(String html) => parseWithInfo(html).items;

  /// 自动检测，返回使用的解析器名称（调试用）
  static String detectParser(String html) {
    final doc = _parseDoc(html);
    for (final parser in _parsers) {
      if (parser.canParse(doc)) {
        return parser.runtimeType.toString();
      }
    }
    return 'NoParser';
  }

  static dom.Document _parseDoc(String html) {
    return htmlParser.parse(html);
  }
}
