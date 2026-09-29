import 'package:dio/dio.dart';
import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/api/home/credit/http.dart' as http;
import 'package:mtbbs/api/home/credit/parse.dart' as parse;

/// 积分公式 API 导出

Future<Map<String, dynamic>> fetch(Dio dio) async {
  final resp = await http.getCreditFormula(dio);
  return parseWithLog(resp, parse.parseResponse);
}
