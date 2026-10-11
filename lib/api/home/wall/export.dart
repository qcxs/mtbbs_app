import 'package:dio/dio.dart';
import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/api/home/wall/http.dart' as http;
import 'package:mtbbs/api/home/wall/parse.dart' as parse;
import 'package:mtbbs/core/parser/xml_helper.dart';

/// 用户留言板 API 导出
///
/// [uid] 为空 → 当前登录用户自己的留言板；非空 → 该 uid 用户的留言板。
/// 只走 PC 模板（见 http.dart）。发布/回复/编辑/删除需登录，且 [formhash]
/// 由 [getWall] 返回后回传（一页共用一个）。

/// 拉取留言板（列表 + formhash + canPost）
Future<Map<String, dynamic>> getWall(
  Dio dio, {
  String uid = '',
  int page = 1,
}) async {
  final resp = await http.getWallPage(dio, uid: uid, page: page);
  return parseWithLog(resp, parse.parseWallPage);
}

/// 发布留言
Future<SubmitResult> postWallComment(
  Dio dio, {
  required String uid,
  required String formhash,
  required String message,
}) async {
  final resp = await http.submitWallComment(
    dio,
    uid: uid,
    formhash: formhash,
    message: message,
  );
  return parseSubmitResponse(safeDecode(resp));
}

/// 回复某条留言（引用 [cid]）
Future<SubmitResult> replyWallComment(
  Dio dio, {
  required String uid,
  required String cid,
  required String formhash,
  required String message,
}) async {
  final resp = await http.submitWallReply(
    dio,
    uid: uid,
    cid: cid,
    formhash: formhash,
    message: message,
  );
  return parseSubmitResponse(safeDecode(resp));
}

/// 编辑自己的留言
Future<SubmitResult> editWallComment(
  Dio dio, {
  required String uid,
  required String cid,
  required String formhash,
  required String message,
}) async {
  final resp = await http.submitWallEdit(
    dio,
    uid: uid,
    cid: cid,
    formhash: formhash,
    message: message,
  );
  return parseSubmitResponse(safeDecode(resp));
}

/// 删除留言
Future<SubmitResult> deleteWallComment(
  Dio dio, {
  required String cid,
  required String formhash,
}) async {
  final resp = await http.submitWallDelete(
    dio,
    cid: cid,
    formhash: formhash,
  );
  return parseSubmitResponse(safeDecode(resp));
}
