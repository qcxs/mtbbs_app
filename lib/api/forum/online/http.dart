import 'package:dio/dio.dart';
import '../../../config/site_config.dart';

/// 在线用户 HTTP 请求
///
/// 使用 PC User-Agent 获取带详情（类型图标）的在线用户列表
Future<Response<String>> getOnlineUsers(Dio dio) {
  return dio.get<String>(
    '/forum.php?showoldetails=yes',
    options: Options(headers: {
      'User-Agent': Site.uaPc,
    }),
  );
}
