import 'package:html/dom.dart' as dom;
import 'package:mtbbs/core/app/page_helper.dart';
import 'package:mtbbs/core/utils/url_util.dart';

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

/// 版块字段（名称 / URL / fid）——在 [scope] 内查找版块链接。
///
/// [selector] 默认匹配 `a[href*=forum-]` / `a[href*=forumdisplay]`；
/// 个别模板版块链接是 `td`/`em` 下的首个 `a`，或作用域已收窄，可传更具体的选择器。
/// [normalize] 为 true 时对 URL 走 [normalizeUrl]（标准搜索模板的 href 是相对地址）。
({String? name, String? url, int? id}) parseBoardFields(
  dom.Element? scope, {
  String selector = 'a[href*="forum-"], a[href*="forumdisplay"]',
  bool normalize = false,
}) {
  final link = scope?.querySelector(selector);
  if (link == null) return (name: null, url: null, id: null);
  var url = link.attributes['href'] ?? '';
  if (normalize && url.isNotEmpty) url = normalizeUrl(url);
  return (
    name: sanitizeText(link.text),
    url: url.isEmpty ? null : url,
    id: url.isEmpty ? null : extractBoardIdFromUrl(url),
  );
}

/// 回复 / 查看数：单元格内 `a` → replies、`em` → views。
///
/// 标准 Discuz 用 `td.num`；克米表格用 `.km_reply a` / `.km_view`，传自定义选择器。
({int? replies, int? views}) parseNumCell(
  dom.Element? cell, {
  String replySelector = 'a',
  String viewSelector = 'em',
}) {
  if (cell == null) return (replies: null, views: null);
  final replyEl = cell.querySelector(replySelector);
  final viewEl = cell.querySelector(viewSelector);
  return (
    replies: replyEl == null ? null : int.tryParse(replyEl.text.trim()),
    views: viewEl == null ? null : int.tryParse(viewEl.text.trim()),
  );
}

/// 精华等级（>0 = 精华帖）——标准 Discuz / 克米**表格**模板把精华渲染为
/// `span.tbox.tdigest`（文本形如「精华 1」，其中数字为精华等级）。无标记返回 null。
///
/// 注意：`filter=digest` 的精华列表里服务端会**抑制**该徽标（`$filter != 'digest'`），
/// 此时解析不到属正常。
int? parseDigestBadge(dom.Element? scope) {
  final el = scope?.querySelector('.tdigest');
  if (el == null) return null;
  final m = RegExp(r'(\d+)').firstMatch(el.text);
  return (m != null ? int.tryParse(m.group(1)!) : null) ?? 1;
}

/// 精华标记（克米**移动卡片**模板）：标题链接内的前置徽标
/// `<span class="bg_c f_f">精</span>`（文本恰为「精」）。命中返回 true。
bool hasDigestBadge(dom.Element? titleLink) {
  if (titleLink == null) return false;
  for (final child in titleLink.children) {
    if (child.localName == 'span' && child.text.trim() == '精') return true;
  }
  return false;
}
