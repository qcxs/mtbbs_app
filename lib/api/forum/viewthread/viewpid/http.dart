import 'package:dio/dio.dart';

/// 单帖详情 HTTP 请求（inajax）

Future<Response<String>> getPostByPid(
  Dio dio, {
  required String tid,
  required String viewpid,
}) {
  return dio.get<String>(
    '/forum.php?mod=viewthread&tid=$tid&viewpid=$viewpid&inajax=1',
  );
}

/// 请求「按 pid 定位回复」链接，取回其重定向目标（**不自动跟随**）
///
/// `forum.php?mod=redirect&goto=findpost&pid=X` 会 301 到
/// `forum.php?mod=viewthread&tid=TID&page=N#pidX` —— 由 Location 即可反推 tid。
/// 显式 `followRedirects: false`：只取 Location，避免把整页帖子拉下来。
Future<Response<String>> getFindpostRedirect(
  Dio dio, {
  required String pid,
}) {
  return dio.get<String>(
    '/forum.php?mod=redirect&goto=findpost&pid=$pid',
    options: Options(
      followRedirects: false,
      validateStatus: (s) => s != null && s < 500,
    ),
  );
}
