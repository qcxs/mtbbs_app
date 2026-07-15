import 'package:dio/dio.dart';
import '../../helpers.dart';
import 'http.dart' as http;
import 'parse.dart' as parse;

/// 用户空间 API 导出
///
/// 查询优先级：[uid] > [username] > 当前登录用户自己
Future<Map<String, dynamic>> getUserProfile(
  Dio dio, {
  String uid = '',
  String username = '',
}) async {
  final resp = await http.getUserProfile(dio, uid: uid, username: username);
  return parse.parseResponse(safeDecode(resp), resp.statusCode ?? 0);
}
