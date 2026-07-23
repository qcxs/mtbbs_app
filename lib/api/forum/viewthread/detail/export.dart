import 'package:dio/dio.dart';
import '../../../helpers.dart';
import 'http.dart' as http;
import 'parse.dart' as parse;

Future<Map<String, dynamic>> getThreadDetail(
  Dio dio, {
  required String tid,
  int page = 1,
  String? authorid,
}) async {
  final resp = await http.getThreadDetail(
    dio,
    tid: tid,
    page: page,
    authorid: authorid,
  );
  return parseWithLog(resp, (b, s) =>
      parse.parseResponse(b, s, page: page, authorid: authorid));
}
