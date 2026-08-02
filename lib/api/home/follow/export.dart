import 'package:dio/dio.dart';
import 'package:mtbbs/api/helpers.dart';
import 'http.dart' as http;
import 'parse.dart' as parse;

/// 关注/粉丝列表 API 导出
///
/// [type]：'following'（关注/我收听的人）、'follower'（粉丝/我的听众）。
/// [uid] 为空 → 当前登录用户自己的列表；非空 → 查看该 uid 用户的列表。
Future<Map<String, dynamic>> getFollowList(
  Dio dio, {
  required String type,
  String uid = '',
  int page = 1,
}) async {
  final resp = await http.getFollowList(dio, type: type, uid: uid, page: page);
  return parseWithLog(resp, parse.parseResponse);
}
