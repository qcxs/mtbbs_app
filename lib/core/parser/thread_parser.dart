import 'package:mtbbs/models/thread_item.dart';
import 'package:mtbbs/core/app/thread_parsers/parser_factory.dart';

/// 解析帖子列表 HTML，返回 ThreadItem 列表。
///
/// 使用 [ThreadListParserFactory] 自动检测并选择合适的解析器。
/// 支持以下 DOM 结构：
/// - 克米模板卡片式（`li.forumlist_li.comiis_znalist`）
/// - 标准 Discuz 表格（`#threadlist th.common`）
/// - 克米模板表格混合（`div.comiis_postlist`）
///
/// 扩展方式：在 [ThreadListParserFactory] 中注册新的解析器。
List<ThreadItem> parseThreadList(String html) {
  return ThreadListParserFactory.parse(html);
}

/// 调试用：检测当前 HTML 适用的解析器名称
String detectThreadListParser(String html) {
  return ThreadListParserFactory.detectParser(html);
}
