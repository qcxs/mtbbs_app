import 'package:dio/dio.dart';

/// 好友列表 HTTP 请求 — 基于 Dio
///
/// baseUrl / UA 由 ApiService 的 BaseOptions 统一提供。
///
/// [uid] 为空 → 当前登录用户自己的好友（view=me）；
/// [uid] 非空 → 查看指定 uid 用户的好友列表。
Future<Response<String>> getFriendList(
  Dio dio, {
  String uid = '',
  int page = 1,
}) {
  if (uid.isNotEmpty) {
    return dio.get<String>(
      '/home.php?mod=space&uid=$uid&do=friend&from=space&page=$page',
    );
  }
  return dio.get<String>(
    '/home.php?mod=space&do=friend&view=me&from=space&page=$page',
  );
}
