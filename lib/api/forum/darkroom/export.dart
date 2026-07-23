import 'package:dio/dio.dart';
import '../../helpers.dart';
import 'http.dart' as http;
import 'parse.dart' as parse;

/// 小黑屋 API 导出

Future<Map<String, dynamic>> getList(Dio dio, {String cid = ''}) async {
  final resp = await http.getList(dio, cid: cid);
  return parseWithLog(resp, parse.parseResponse);
}
