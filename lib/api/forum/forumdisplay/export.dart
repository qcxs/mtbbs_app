import 'package:dio/dio.dart';
import '../../helpers.dart';
import 'http.dart' as http;
import 'parse.dart' as parse;

Future<Map<String, dynamic>> getForumThreads(Dio dio, {required String fid, String orderby = '', String filter = '', int page = 1}) async {
  final resp = await http.getForumThreads(dio, fid: fid, orderby: orderby, filter: filter, page: page);
  return parseWithLog(resp, parse.parseResponse);
}
