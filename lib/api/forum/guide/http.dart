import 'package:dio/dio.dart';

/// 导读 HTTP 请求 — 基于 Dio
///
/// baseUrl 由 Dio 实例的 BaseOptions 提供

/// 获取帖子列表
Future<Response<String>> getThreadList(
  Dio dio, {
  String view = 'newthread',
  int page = 1,
}) {
  return dio.get<String>('/forum.php?mod=guide&index=1&view=$view&page=$page&mobile=2');
}
