import 'package:dio/dio.dart';
import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/api/home/notice/http.dart' as http;
import 'package:mtbbs/api/home/notice/parse.dart' as parse;

/// [view] / [type] 见 [http.getNoticeList]
/// （`system` 系统提醒 / `manage` 管理工作 / `interactive` 坛友互动…）
Future<Map<String, dynamic>> getNoticeList(
  Dio dio, {
  int page = 1,
  String view = 'system',
  String type = '',
}) async {
  final resp = await http.getNoticeList(
    dio,
    page: page,
    view: view,
    type: type,
  );
  return parseWithLog(resp, parse.parseResponse);
}
