import 'package:dio/dio.dart';
import 'package:mtbbs/core/site_store.dart';

/// 导读 HTTP 请求 — 基于 Dio
///
/// baseUrl 由 Dio 实例的 BaseOptions 提供
/// UA 由当前站点配置决定（用户可切换移动/桌面）。

/// 获取帖子列表
Future<Response<String>> getThreadList(
  Dio dio, {
  String view = 'newthread',
  int page = 1,
}) {
  final site = SiteStore.instance;
  return dio.get<String>(
    '/forum.php?mod=guide&index=1&view=$view&page=$page',
    options: Options(headers: {'User-Agent': site.userAgent}),
  );
}
