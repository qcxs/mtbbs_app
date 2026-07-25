import 'package:dio/dio.dart';
import 'package:mtbbs/config/site_config.dart';

/// 系统提醒 HTTP 请求

Future<Response<String>> getSystemList(Dio dio, {int page = 1}) {
  final pageParam = page > 1 ? '&page=$page' : '';
  return dio.get<String>(
    '/home.php?mod=space&do=notice&view=system$pageParam',
    options: Options(headers: {'User-Agent': Site.uaPc}),
  );
}
