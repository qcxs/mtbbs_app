import 'package:dio/dio.dart';
import 'package:mtbbs/core/parser/page_fetcher.dart';
import 'package:mtbbs/core/parser/xml_helper.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/api/forum/post/http.dart' as http;
import 'package:mtbbs/api/forum/post/parse.dart' as parse;

/// 拉取编辑器页面并解析表单字段（发帖/评论/回复/编辑共用）。
Future<PageFormData> fetchEditorPage(
  Dio dio, {
  required String type,
  String fid = '',
  String tid = '',
  String pid = '',
  String? repquote,
}) async {
  final url = PageFetcher.buildUrl(
    type: type,
    fid: fid,
    tid: tid,
    pid: pid,
    repquote: repquote,
  );
  if (url.isEmpty) return const PageFormData(success: false, error: 'URL 为空');
  final resp = await http.getEditorPage(
    dio,
    type: type,
    fid: fid,
    tid: tid,
    pid: pid,
    repquote: repquote,
  );
  return PageFetcher.parsePage(safeDecode(resp), url: url);
}

/// 提交编辑（帖子/回复）。
Future<SubmitResult> submitEditPost(
  Dio dio, {
  required String fid,
  required String tid,
  required String pid,
  required String formhash,
  required String posttime,
  required String subject,
  required String message,
  Map<String, String> attachNew = const {},
}) async {
  final resp = await http.submitEdit(
    dio,
    fid: fid,
    tid: tid,
    pid: pid,
    formhash: formhash,
    posttime: posttime,
    subject: subject,
    message: message,
    attachNew: attachNew,
  );
  final result = parse.parseEditResponse(
    safeDecode(resp),
    resp.statusCode ?? 0,
    resp.headers.value('location') ?? '',
  );
  AppLogger.i('PARSE', 'post edit → ${result.success} ${result.message}');
  return result;
}

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
