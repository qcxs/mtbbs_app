import 'package:html/dom.dart' as dom;
import 'package:mtbbs/models/thread_item.dart';

/// 帖子列表解析器接口 — 策略模式
///
/// 每个解析器负责识别并解析一种特定的 Discuz 帖子列表 DOM 结构。
/// 通过 [canParse] 判断是否适应当前 HTML，[parse] 提取数据。
abstract class ThreadListParser {
  /// 判断当前解析器是否能处理此文档
  bool canParse(dom.Document doc);

  /// 解析文档，返回帖子列表
  List<ThreadItem> parse(dom.Document doc);
}
