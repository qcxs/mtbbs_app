import 'package:dio/dio.dart';
import '../../../../config/site_config.dart';

/// 单帖详情 HTTP 请求（inajax）

Future<Response<String>> getPostByPid(
  Dio dio, {
  required String tid,
  required String viewpid,
}) {
  return dio.get<String>(
    '/forum.php?mod=viewthread&tid=$tid&viewpid=$viewpid&inajax=1',
    options: Options(
      headers: {
        'X-Requested-With': 'XMLHttpRequest',
        'User-Agent': SiteConfig.uaPc,
      },
    ),
  );
}
