import 'package:dio/dio.dart';
import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/api/home/follow/http.dart' as http;
import 'package:mtbbs/api/home/follow/parse.dart' as parse;

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

/// 关注（收听）指定用户。
///
/// [formhash] 通常由用户资料页解析得到（profile['followHash']）；
/// 为空时自动重新拉取资料页补齐。若资料页显示「已关注」，直接返回成功。
Future<Map<String, dynamic>> followUser(
  Dio dio, {
  required String uid,
  String formhash = '',
}) async {
  var hash = formhash.trim();
  if (hash.isEmpty) {
    final profileResp = await http.getProfilePage(dio, uid: uid);
    final state = parseWithLog(profileResp, parse.parseFollowStateResponse);
    if (state['success'] != true) return state;
    if (state['followed'] == true) {
      return {'success': true, 'followed': true, 'message': '已关注'};
    }
    hash = state['formhash']?.toString() ?? '';
  }
  if (hash.isEmpty) {
    return {'success': false, 'message': '缺少 formhash，请刷新页面后重试'};
  }

  final resp = await http.followUser(dio, uid: uid, formhash: hash);
  return parseWithLog(
    resp,
    (b, s) => parse.parseFollowResult(b, s, follow: true),
  );
}

/// 取消关注（取消收听）指定用户。
Future<Map<String, dynamic>> unfollowUser(
  Dio dio, {
  required String uid,
}) async {
  final resp = await http.unfollowUser(dio, uid: uid);
  return parseWithLog(
    resp,
    (b, s) => parse.parseFollowResult(b, s, follow: false),
  );
}
