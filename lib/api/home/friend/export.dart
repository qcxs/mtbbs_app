import 'package:dio/dio.dart';
import 'package:mtbbs/api/helpers.dart';
import 'http.dart' as http;
import 'parse.dart' as parse;

/// 好友列表 API 导出
///
/// [uid] 为空 → 当前登录用户自己的好友；非空 → 查看该 uid 用户的好友。
Future<Map<String, dynamic>> getFriendList(
  Dio dio, {
  String uid = '',
  int page = 1,
}) async {
  final resp = await http.getFriendList(dio, uid: uid, page: page);
  return parseWithLog(resp, parse.parseResponse);
}
