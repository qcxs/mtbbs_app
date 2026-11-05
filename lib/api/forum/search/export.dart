import 'package:dio/dio.dart';
import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/core/app/browse_mode.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/api/forum/search/http.dart' as http;
import 'package:mtbbs/api/forum/search/parse.dart' as parse;

/// 站内搜索 API 导出
///
/// 首次调用（[searchId] 为空）会发起新搜索并把结果里的 `searchId` 一并返回；
/// 后续翻页把该 `searchId` 回传即可。
Future<Map<String, dynamic>> searchThreads(
  Dio dio, {
  required String keyword,
  int page = 1,
  String? searchId,
  String srchFilter = '',
  String? charset,
}) async {
  final resp = await http.searchThreads(
    dio,
    keyword: keyword,
    page: page,
    searchId: searchId,
    srchFilter: srchFilter,
    charset: charset,
  );
  final data = parseWithLog(resp, parse.parseResponse);
  // 站点把搜索外包给 Bing（52pojie 的 search.php 会 302 到 bing.com/search），
  // 最终页面不是 Discuz DOM，解析必然 noMatch。把最终 URL 交给页面，
  // 由它自动改用内置浏览器打开。
  final finalHost = resp.realUri.host.toLowerCase();
  if (finalHost == 'bing.com' || finalHost.endsWith('.bing.com')) {
    data['externalSearchUrl'] = resp.realUri.toString();
  }
  // searchid 只在重定向后的最终 URL 上（空结果页 body 里没有分页链接）。
  // 不能用 realUri.queryParameters：它会按 UTF-8 解码整个 query，GBK 站点
  // 的 highlight=%B9%AB%CA%BD 会抛 FormatException（见 _queryValue）。
  final sid = _queryValue(resp.realUri, 'searchid');
  if (sid != null && sid.isNotEmpty) {
    data['searchId'] = sid;
  } else {
    data['searchId'] ??= parse.extractSearchId(safeDecode(resp));
  }
  return data;
}

/// 搜索结果页完整 URL（供"在浏览器中打开"用）
///
/// 传入 [searchId] 时直接打开该次搜索的结果页（可带 [page]），**不会**在服务端
/// 新建搜索、也不触发搜索频率限制；为空时退化为"按关键词/过滤条件发起新搜索"的 URL。
String searchPageUrl({
  required String keyword,
  String? searchId,
  int page = 1,
  String srchFilter = '',
  String? baseUrl,
  String? charset,
}) {
  final base = baseUrl ?? SiteStore.instance.baseUrl;
  final cs = charset ?? resolveRequestCharset();
  return '$base${http.searchPath(keyword: keyword, page: page, searchId: searchId, srchFilter: srchFilter, charset: cs)}';
}

/// 只取指定查询参数，不碰其它键。
///
/// `Uri.queryParameters` 会把**所有**参数值按 UTF-8 解码；GBK 站点（如 52pojie）
/// 的 URL 常带 `highlight=%B9%AB%CA%BD`，会抛
/// `FormatException: Unexpected extension byte`。
String? _queryValue(Uri uri, String key) {
  final query = uri.query;
  if (query.isEmpty) return null;
  for (final part in query.split('&')) {
    final eq = part.indexOf('=');
    final k = eq < 0 ? part : part.substring(0, eq);
    if (k != key) continue;
    final raw = eq < 0 ? '' : part.substring(eq + 1);
    try {
      return Uri.decodeQueryComponent(raw);
    } catch (_) {
      return raw;
    }
  }
  return null;
}
