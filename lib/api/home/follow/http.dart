import 'package:dio/dio.dart';

/// 关注/粉丝列表 HTTP 请求 — 基于 Dio
///
/// baseUrl / UA 由 ApiService 的 BaseOptions 统一提供。
///
/// [type]：'following'（我收听的人/关注）、'follower'（我的听众/粉丝）。
/// [uid] 为空 → 当前登录用户自己的列表；非空 → 查看指定 uid 用户的列表。
Future<Response<String>> getFollowList(
  Dio dio, {
  required String type,
  String uid = '',
  int page = 1,
}) {
  final base = '/home.php?mod=follow&do=$type';
  if (uid.isNotEmpty) {
    return dio.get<String>('$base&uid=$uid&page=$page');
  }
  return dio.get<String>('$base&page=$page');
}
