/// 用户 uid 提取工具
///
/// Discuz 的用户空间链接**没有统一格式**，同一站点换套模板就会变：
/// - 伪静态：`space-uid-1155.html`、`uid-1155.html`
/// - 查询串：`home.php?mod=space&uid=1155`、`space.php?uid=1155`
/// - 纯参数：`…?uid=1155`
///
/// 各处解析各写一个正则，漏掉一种写法就会让整列 uid 为空（52pojie 实测：
/// `home.php?mod=space&uid=879080`，只匹配 `uid-数字` 必然取不到），UI 随后
/// 拼出 `/user/` 这类非法路由。统一走这里，新增站点/模板只需补一种模式。
library;

/// 从链接中提取用户 uid（字符串；识别不了返回 null）。
///
/// [strict] 为 true 时只认**用户空间链接**：
/// `space-uid-N` / `uid-N` / `mod=space&…uid=N` / `space.php?uid=N`。
///
/// 需要严格模式的场景：页面里混着带 `uid=` 但**不是用户**的操作链接，例如
/// 私信删除菜单 `…&deletepm_deluid[]=1&uid=1`——宽松匹配会把 1 当成对方 uid。
String? uidFromHref(String? href, {bool strict = false}) {
  final url = href?.replaceAll('&amp;', '&').trim() ?? '';
  if (url.isEmpty) return null;

  // 伪静态：space-uid-123.html / uid-123.html
  final staticMatch = RegExp(r'(?:^|[^\w])uid[-/](\d+)').firstMatch(url);
  if (staticMatch != null) return staticMatch.group(1);

  // 用户空间查询串：home.php?mod=space&uid=123 / space.php?uid=123
  // 用 `mod=space` 完整匹配，避免把 `mod=spacecp` 这类操作链接当成用户空间
  final isSpaceLink =
      RegExp(r'[?&]mod=space(?:&|#|$)').hasMatch(url) ||
      RegExp(r'(?:^|[?&/])space\.php(?:[?#]|$)').hasMatch(url);
  if (isSpaceLink) {
    final uid = RegExp(r'[?&]uid=(\d+)').firstMatch(url)?.group(1);
    if (uid != null) return uid;
  }
  if (strict) return null;

  // 宽松兜底：任意 uid=123 / uid-123
  return RegExp(r'[?&]uid=(\d+)').firstMatch(url)?.group(1) ??
      RegExp(r'\buid[=-](\d+)').firstMatch(url)?.group(1);
}
