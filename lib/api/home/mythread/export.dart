import 'package:dio/dio.dart';
import '../../helpers.dart';
import 'http.dart' as http;
import 'parse.dart' as parse;

/// 我的帖子/回复 API 导出

Future<Map<String, dynamic>> getMyThreads(
  Dio dio, {
  int page = 1,
  String? uid,
  String? type,
}) async {
  final resp = await http.getMyThreads(dio, page: page, uid: uid, type: type);
  return parseWithLog(resp, parse.parseResponse);
}
