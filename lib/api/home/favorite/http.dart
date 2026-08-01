import 'package:dio/dio.dart';

/// 收藏列表 HTTP 请求
Future<Response<String>> getFavorites(Dio dio, {int page = 1}) {
  return dio.get<String>(
    '/home.php?mod=space&do=favorite&view=me&page=$page',
  );
}
