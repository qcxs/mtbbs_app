import 'package:dio/dio.dart';
import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/api/home/system/http.dart' as http;
import 'package:mtbbs/api/home/system/parse.dart' as parse;

Future<Map<String, dynamic>> getSystemList(Dio dio, {int page = 1}) async {
  final resp = await http.getSystemList(dio, page: page);
  return parseWithLog(resp, parse.parseResponse);
}
