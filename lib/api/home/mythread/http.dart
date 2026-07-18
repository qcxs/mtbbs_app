import 'package:dio/dio.dart';

/// 我的帖子列表 HTTP 请求（手机 UA）
Future<Response<String>> getMyThreads(Dio dio, {int page = 1, String? uid, String? type}) {
  final params = StringBuffer('/home.php?mod=space&do=thread');
  params.write('&page=$page');
  if (uid != null && uid.isNotEmpty) params.write('&uid=$uid');
  if (type != null && type.isNotEmpty) params.write('&type=$type');
  return dio.get<String>(
    params.toString(),
    options: Options(headers: {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    }),
  );
}
