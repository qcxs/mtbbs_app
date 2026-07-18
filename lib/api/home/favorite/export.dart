import 'package:dio/dio.dart';
import '../../helpers.dart';
import 'http.dart' as http;
import 'parse.dart' as parse;

/// 收藏 API 导出

Future<Map<String, dynamic>> fetchFavorites(Dio dio, {int page = 1}) async {
  final resp = await http.getFavorites(dio, page: page);
  return parse.parseResponse(safeDecode(resp), resp.statusCode ?? 0);
}
