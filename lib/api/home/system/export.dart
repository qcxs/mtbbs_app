import 'package:dio/dio.dart';
import '../../helpers.dart';
import 'http.dart' as http;
import 'parse.dart' as parse;

Future<Map<String, dynamic>> getSystemList(Dio dio, {int page = 1}) async {
  final resp = await http.getSystemList(dio, page: page);
  return parseWithLog(resp, parse.parseResponse);
}
