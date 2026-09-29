import 'package:dio/dio.dart';
import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/api/forum/online/http.dart' as http;
import 'package:mtbbs/api/forum/online/parse.dart' as parse;

/// 在线用户 API 导出

Future<Map<String, dynamic>> fetchOnlineUsers(Dio dio) async {
  final resp = await http.getOnlineUsers(dio);
  return parseWithLog(resp, parse.parseResponse);
}
