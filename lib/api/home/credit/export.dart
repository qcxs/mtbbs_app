import 'package:dio/dio.dart';
import '../../helpers.dart';
import 'http.dart' as http;
import 'parse.dart' as parse;

/// 积分公式 API 导出

Future<Map<String, dynamic>> fetch(Dio dio) async {
  final resp = await http.getCreditFormula(dio);
  return parse.parseResponse(safeDecode(resp), resp.statusCode ?? 0);
}
