import 'package:html/dom.dart' as dom;
import 'package:mtbbs/core/app/page_helper.dart';

/// 帖子列表解析器共享工具
///
/// 供 thread_parsers/ 下各解析器复用，避免重复实现。

/// 从用户空间链接中提取 uid（如 `space-uid-123.html`、`?uid=123`）
int? extractUidFromUrl(String url) {
  try {
    final uri = Uri.parse(url);
    final uidStr = uri.queryParameters['uid'];
    if (uidStr != null) return int.tryParse(uidStr);
    final m = RegExp(r'space-uid-(\d+)').firstMatch(url);
    if (m != null) return int.tryParse(m.group(1)!);
    return null;
  } catch (_) {
    return null;
  }
}

/// 从帖子链接中提取 tid
int? extractThreadIdFromUrl(String url) {
  final result = parseThreadUrl(url);
  return result['tid'] != 0 ? result['tid'] : null;
}

/// 从版块链接中提取 fid（如 `forum-12.html`、`forum_12`）
int? extractBoardIdFromUrl(String url) {
  final m = RegExp(r'forum[_-](\d+)').firstMatch(url);
  return m != null ? int.tryParse(m.group(1)!) : null;
}

/// 提取文本中的纯数字（统计类字段，如 回复/查看 数）
int? extractIntFromText(String text) {
  final cleaned = text.replaceAll(RegExp(r'[^\d]'), '');
  return cleaned.isEmpty ? null : int.parse(cleaned);
}

/// 提取元素文本，跳过指定标签（如 {span, i} 图标字体）
String cleanElementText(dom.Element el, {Set<String> excludeTags = const {}}) {
  final buf = StringBuffer();
  for (final node in el.nodes) {
    if (node is dom.Element && excludeTags.contains(node.localName)) continue;
    buf.write(node.text);
  }
  return buf.toString().trim();
}
