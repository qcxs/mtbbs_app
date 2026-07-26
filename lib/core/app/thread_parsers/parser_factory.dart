import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as htmlParser;
import 'package:mtbbs/models/thread_item.dart';
import 'thread_list_parser.dart';
import 'comiis_card_parser.dart';
import 'discuz_table_parser.dart';
import 'comiis_table_parser.dart';
import 'space_thread_parser.dart';

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

  /// 自动检测并解析帖子列表 HTML
  static List<ThreadItem> parse(String html) {
    final doc = _parseDoc(html);
    for (final parser in _parsers) {
      if (parser.canParse(doc)) {
        return parser.parse(doc);
      }
    }
    return [];
  }

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
