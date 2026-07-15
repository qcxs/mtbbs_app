import 'package:dio/dio.dart';
import 'package:mtbbs/core/xml_helper.dart';
import '../../helpers.dart';
import 'http.dart' as http;

/// 发布新帖（纯提交，formhash/posttime 由调用方提供）
Future<SubmitResult> submitNewPost(
  Dio dio, {
  required String fid,
  required String formhash,
  required String posttime,
  required String subject,
  required String message,
  Map<String, String> attachNew = const {},
}) async {
  final resp = await http.submitNewThread(
    dio,
    fid: fid,
    formhash: formhash,
    posttime: posttime,
    subject: subject,
    message: message,
    attachNew: attachNew,
  );
  return parseSubmitResponse(safeDecode(resp));
}

/// 提交回复（纯提交，formhash/posttime 由调用方提供）
Future<SubmitResult> submitReply(
  Dio dio, {
  required String fid,
  required String tid,
  required String formhash,
  required String posttime,
  required String message,
  String? noticeauthor,
  String? noticetrimstr,
  String? noticeauthormsg,
  String? reppid,
  Map<String, String> attachNew = const {},
}) async {
  final resp = await http.submitReply(
    dio,
    fid: fid,
    tid: tid,
    formhash: formhash,
    posttime: posttime,
    message: message,
    noticeauthor: noticeauthor,
    noticetrimstr: noticetrimstr,
    noticeauthormsg: noticeauthormsg,
    reppid: reppid,
    attachNew: attachNew,
  );
  return parseSubmitResponse(safeDecode(resp));
}
