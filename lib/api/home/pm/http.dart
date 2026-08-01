import 'package:dio/dio.dart';

/// PM 消息列表 HTTP 请求

/// 获取私人消息列表
/// [page] 页码，从 1 开始
Future<Response<String>> getPmList(Dio dio, {int page = 1}) {
  final pageParam = page > 1 ? '&page=$page' : '';
  return dio.get<String>(
    '/home.php?mod=space&do=pm&filter=privatepm$pageParam',
  );
}
