import 'package:dio/dio.dart';
import 'package:mtbbs/api/helpers.dart';
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
}) async {
  final resp = await http.searchThreads(
    dio,
    keyword: keyword,
    page: page,
    searchId: searchId,
  );
  final data = parseWithLog(resp, parse.parseResponse);
  // searchid 只在重定向后的最终 URL 上（空结果页 body 里没有分页链接）
  final sid = resp.realUri.queryParameters['searchid'];
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
/// 新建搜索、也不触发搜索频率限制；为空时退化为"按关键词发起新搜索"的 URL。
String searchPageUrl({
  required String keyword,
  String? searchId,
  int page = 1,
}) {
  final base = SiteStore.instance.baseUrl;
  return '$base${http.searchPath(keyword: keyword, page: page, searchId: searchId)}';
}
