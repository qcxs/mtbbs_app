import 'package:dio/dio.dart';
import '../../helpers.dart';
import 'http.dart' as http;
import 'parse.dart' as parse;

/// PM 消息 API 导出

/// 获取私人消息列表
Future<Map<String, dynamic>> getPmList(Dio dio, {int page = 1}) async {
  final resp = await http.getPmList(dio, page: page);
  return parseWithLog(resp, parse.parseResponse);
}
