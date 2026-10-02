import 'package:dio/dio.dart';
import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/api/home/pm/http.dart' as http;
import 'package:mtbbs/api/home/pm/parse.dart' as parse;
import 'package:mtbbs/core/parser/xml_helper.dart';
import 'package:mtbbs/core/utils/logger.dart';

/// PM 私信 API 导出

/// 获取私人消息列表（会话列表）
Future<Map<String, dynamic>> getPmList(Dio dio, {int page = 1}) async {
  final resp = await http.getPmList(dio, page: page);
  return parseWithLog(resp, parse.parseResponse);
}

/// 获取与某用户的私信会话（消息列表）
///
/// [page] 为 0/不传 = 最新一页，传 1 = 最旧一页（Discuz page 从最旧页起算）。
Future<Map<String, dynamic>> getPmView(
  Dio dio, {
  required String touid,
  int page = 0,
}) async {
  final resp = await http.getPmView(dio, touid: touid, page: page);
  return parseWithLog(resp, parse.parsePmView);
}

/// 发送私信
///
/// [formhash] 可选：会话页已解析到时直接传入（省一次请求），
/// 为空则自动从"发送短消息"页获取（新会话场景必备）。
Future<SubmitResult> sendPm(
  Dio dio, {
  required String touid,
  required String message,
  String formhash = '',
}) async {
  final hash = formhash.isNotEmpty ? formhash : await _fetchFormhash(dio, touid);
  if (hash.isEmpty) {
    AppLogger.w('PARSE', 'pm send: 未取到 formhash（未登录或页面结构变更）');
    return const SubmitResult(success: false, message: '获取表单令牌失败，请重新登录');
  }
  final resp = await http.submitPm(
    dio,
    touid: touid,
    formhash: hash,
    message: message,
  );
  return parseSubmitResponse(safeDecode(resp));
}

/// 从"发送短消息"页取 formhash（会话为空时 subop=view 无回复表单）
Future<String> _fetchFormhash(Dio dio, String touid) async {
  final resp = await http.getPmComposePage(dio, touid: touid);
  return parse.extractFormhash(safeDecode(resp));
}
