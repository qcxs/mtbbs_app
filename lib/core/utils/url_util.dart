import 'package:mtbbs/core/app/site_store.dart';

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
/// [base] 可覆盖默认站点 baseUrl（用于注入自定义 base，如 BBCode2Html）。
String normalizeUrl(String url, {String? base}) {
  final parsed = Uri.tryParse(url);
  if (parsed == null) return url;
  if (parsed.isAbsolute) return url;
  // 协议相对 //host/path → https://host/path
  if (url.startsWith('//')) return 'https:$url';
  // 相对路径 → 基于 baseUrl（缺省为站点 baseUrl）解析
  final baseUrl = base ?? SiteStore.instance.baseUrl;
  return Uri.parse(baseUrl).resolve(url).toString();
}
