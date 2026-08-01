import 'package:dio/dio.dart';

/// 在线用户 HTTP 请求
///
/// 依赖 ApiService 统一注入的 PC User-Agent 获取带详情（类型图标）的在线用户列表
Future<Response<String>> getOnlineUsers(Dio dio) {
  return dio.get<String>('/forum.php?showoldetails=yes');
}
