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

/// 关注（收听）指定用户。
///
/// 与 PC/移动模板页面上「收听」按钮同一入口：
/// `home.php?mod=spacecp&ac=follow&op=add&hash={formhash}&fuid={uid}`。
/// [formhash] 取自用户资料页的 `#followmod` 链接（页面解析所得）。
/// `inajax=1` 让服务端返回 XML 片段（纯提示文案），而非整页跳转。
Future<Response<String>> followUser(
  Dio dio, {
  required String uid,
  required String formhash,
}) {
  return dio.get<String>(
    '/home.php?mod=spacecp&ac=follow&op=add'
    '&hash=$formhash&fuid=$uid&inajax=1',
  );
}

/// 取消关注（取消收听）指定用户。
///
/// 服务端不校验 formhash，只需要 `fuid`：
/// `home.php?mod=spacecp&ac=follow&op=del&fuid={uid}`。
Future<Response<String>> unfollowUser(Dio dio, {required String uid}) {
  return dio.get<String>(
    '/home.php?mod=spacecp&ac=follow&op=del&fuid=$uid&inajax=1',
  );
}

/// 获取用户资料页（用于补齐关注所需的 formhash / 当前关注状态）。
Future<Response<String>> getProfilePage(Dio dio, {required String uid}) {
  return dio.get<String>('/home.php?mod=space&uid=$uid&do=profile');
}
