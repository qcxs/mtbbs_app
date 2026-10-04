import 'package:dio/dio.dart';
import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/api/home/space/http.dart' as http;
import 'package:mtbbs/api/home/space/parse.dart' as parse;

/// 供页面/设置层读取与写入"个人空间数据源覆盖"（'mobile' | 'desktop' | ''）。
export 'http.dart' show spaceSourceOverride, applySpaceSourceOverride;

/// 用户空间 API 导出
///
/// 查询优先级：[uid] > [username] > 当前登录用户自己
Future<Map<String, dynamic>> getUserProfile(
  Dio dio, {
  String uid = '',
  String username = '',
}) async {
  final resp = await http.getUserProfile(dio, uid: uid, username: username);
  return parseWithLog(resp, parse.parseResponse);
}
