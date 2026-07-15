import 'package:dio/dio.dart';
import '../../../helpers.dart';
import 'http.dart' as http;
import 'parse.dart' as parse;

Future<Map<String, dynamic>> getThreadDetail(Dio dio, {required String tid, int page = 1}) async {
  final resp = await http.getThreadDetail(dio, tid: tid, page: page);
  return parse.parseResponse(safeDecode(resp), resp.statusCode ?? 0, page: page);
}
