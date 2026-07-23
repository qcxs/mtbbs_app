import 'package:dio/dio.dart';
import '../../helpers.dart';
import 'http.dart' as http;
import 'parse.dart' as parse;

/// 在线用户 API 导出

Future<Map<String, dynamic>> fetchOnlineUsers(Dio dio) async {
  final resp = await http.getOnlineUsers(dio);
  return parseWithLog(resp, parse.parseResponse);
}
