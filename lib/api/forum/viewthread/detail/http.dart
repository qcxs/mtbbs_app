import 'package:dio/dio.dart';
import '../../../../config/site_config.dart';

Future<Response<String>> getThreadDetail(
  Dio dio, {
  required String tid,
  int page = 1,
  String? authorid,
}) {
  var url = '/forum.php?mod=viewthread&tid=$tid&page=$page';
  if (authorid != null && authorid.isNotEmpty) {
    url += '&authorid=$authorid';
  }
  return dio.get<String>(
    url,
    options: Options(headers: {'User-Agent': Site.uaPc}),
  );
}
