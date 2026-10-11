import 'package:dio/dio.dart';
import 'package:mtbbs/core/app/browse_mode.dart';

/// 我的帖子列表 HTTP 请求（UA 使用站点配置，默认移动端）
Future<Response<String>> getMyThreads(
  Dio dio, {
  int page = 1,
  String? uid,
  String? type,
}) {
  final params = StringBuffer('/home.php?mod=space&do=thread');
  params.write('&page=$page');
  if (uid != null && uid.isNotEmpty) params.write('&uid=$uid');
  if (type != null && type.isNotEmpty) params.write('&type=$type');
  return dio.get<String>(
    params.toString(),
    options: Options(headers: {'User-Agent': resolveRequestUserAgent()}),
  );
}
