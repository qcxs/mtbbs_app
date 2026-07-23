import 'package:dio/dio.dart';
import '../../../helpers.dart';
import 'http.dart' as http;
import 'parse.dart' as parse;

Future<Map<String, dynamic>> getPostByPid(Dio dio, {required String tid, required String viewpid}) async {
  final resp = await http.getPostByPid(dio, tid: tid, viewpid: viewpid);
  return parseWithLog(resp, parse.parseResponse);
}
