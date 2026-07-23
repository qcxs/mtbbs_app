import 'package:dio/dio.dart';
import '../../helpers.dart';
import 'http.dart' as http;
import 'parse.dart' as parse;

/// 获取论坛导航（版块列表）
Future<Map<String, dynamic>> fetchForumNav(Dio dio) async {
  final resp = await http.getForumNav(dio);
  return parseWithLog(resp, parse.parseResponse);
}
