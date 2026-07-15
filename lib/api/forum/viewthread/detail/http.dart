import 'package:dio/dio.dart';
import '../../../../config/site_config.dart';

Future<Response<String>> getThreadDetail(
  Dio dio, {
  required String tid,
  int page = 1,
}) {
  return dio.get<String>(
    '/forum.php?mod=viewthread&tid=$tid&page=$page',
    options: Options(headers: {'User-Agent': SiteConfig.uaPc}),
  );
}
