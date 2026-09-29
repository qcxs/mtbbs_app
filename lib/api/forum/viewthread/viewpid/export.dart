import 'package:dio/dio.dart';
import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/api/forum/viewthread/viewpid/http.dart' as http;
import 'package:mtbbs/api/forum/viewthread/viewpid/parse.dart' as parse;

/// 获取单帖详情（表情还原由解析层自行从 EmojiService 读取当前站点数据）。
Future<Map<String, dynamic>> getPostByPid(
  Dio dio, {
  required String tid,
  required String viewpid,
}) async {
  final resp = await http.getPostByPid(dio, tid: tid, viewpid: viewpid);
  return parseWithLog(resp, parse.parseResponse);
}
