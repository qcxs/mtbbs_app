import 'package:dio/dio.dart';

/// 从 Dio Response 中安全解码响应体
/// 处理 charset=utf-8 和自动解码
String safeDecode(Response<String> resp) => resp.data ?? '';
