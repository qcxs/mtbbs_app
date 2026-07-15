import 'package:dio/dio.dart';

/// 用户状态 HTTP 请求
///
/// 返回 JSON 格式的登录用户状态。
/// 未登录时 uid 为 "0"，登录时包含 userstatus HTML。
Future<Response<String>> getUserStatus(Dio dio) {
  return dio.get<String>('/misc.php?mod=userstatus', options: Options(
    headers: {
      'X-Requested-With': 'XMLHttpRequest',
    },
  ));
}
