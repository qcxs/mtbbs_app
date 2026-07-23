import 'package:dio/dio.dart';
import '../../helpers.dart';
import 'http.dart' as http;
import 'parse.dart' as parse;

/// 我的帖子 API 导出

/// 获取帖子提醒列表
/// [type] 子类型：post（帖子）/ at（提到我的）
Future<Map<String, dynamic>> getMypostList(
  Dio dio, {
  int page = 1,
  String type = 'post',
}) async {
  final resp = await http.getMypostList(dio, page: page, type: type);
  return parseWithLog(resp, parse.parseResponse);
}
