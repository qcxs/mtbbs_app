import 'package:dio/dio.dart';
import 'package:mtbbs/config/site_config.dart';

/// 用户空间主页 HTTP 请求 — 基于 Dio
///
/// baseUrl 由 Dio 实例的 BaseOptions 提供
/// 注意：此接口需要 PC User-Agent，桌面版 HTML

/// 获取用户个人资料页面
///
/// 查询优先级：[uid] > [username] > 当前登录用户自己
/// - [uid] 不为空 → 按 uid 查询
/// - [username] 不为空 → 按用户名查询
/// - 两者都为空 → 返回当前登录用户自己的资料
Future<Response<String>> getUserProfile(
  Dio dio, {
  String uid = '',
  String username = '',
}) {
  final path = _buildPath(uid, username);
  return dio.get<String>(
    path,
    options: Options(headers: {'User-Agent': Site.uaPc}),
  );
}

String _buildPath(String uid, String username) {
  if (uid.isNotEmpty) {
    return '/home.php?mod=space&uid=$uid&do=profile';
  }
  if (username.isNotEmpty) {
    return '/home.php?mod=space&username=${Uri.encodeComponent(username)}&do=profile';
  }
  return '/home.php?mod=space&do=profile';
}
