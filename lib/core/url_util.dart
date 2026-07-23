import 'package:mtbbs/core/site_store.dart';

/// URL 统一工具
///
/// 使用 Dart 标准库 [Uri.resolve] 实现完整的 URL 解析，
/// 行为与浏览器一致。
///
/// 用法：
/// ```dart
/// normalizeUrl('forum.php?mod=image&aid=2')
/// // → http://discuz.qcxs.top/forum.php?mod=image&aid=2
///
/// normalizeUrl('//cdn.com/a.jpg')
/// // → https://cdn.com/a.jpg
///
/// normalizeUrl('./template/none.png')
/// // → http://discuz.qcxs.top/template/none.png
///
/// normalizeUrl('https://host.com/a.jpg')
/// // → https://host.com/a.jpg
/// ```
String normalizeUrl(String url) {
  final parsed = Uri.tryParse(url);
  if (parsed == null) return url;
  if (parsed.isAbsolute) return url;
  // 协议相对 //host/path → https://host/path
  if (url.startsWith('//')) return 'https:$url';
  // 相对路径 → 基于站点 baseUrl 解析
  return Uri.parse(SiteStore.instance.baseUrl).resolve(url).toString();
}
