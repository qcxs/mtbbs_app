import 'package:dio/dio.dart';
import 'package:mtbbs/config/site_config.dart';

/// 论坛导航浮动窗口 HTTP 请求
Future<Response<String>> getForumNav(Dio dio) {
  return dio.get<String>(
    '/forum.php?mod=misc&action=nav&infloat=yes&handlekey=nav&inajax=1&ajaxtarget=fwin_content_nav',
    options: Options(headers: {'User-Agent': Site.uaPc}),
  );
}
