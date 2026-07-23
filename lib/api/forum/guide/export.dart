import 'package:dio/dio.dart';
import '../../helpers.dart';
import 'http.dart' as http;
import 'parse.dart' as parse;

/// 导读 API 导出

Future<Map<String, dynamic>> getThreadList(
  Dio dio, {
  String view = 'newthread',
  int page = 1,
}) async {
  final resp = await http.getThreadList(dio, view: view, page: page);
  return parseWithLog(resp, parse.parseResponse);
}
