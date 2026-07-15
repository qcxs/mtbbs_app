import 'package:dio/dio.dart';
import '../../helpers.dart';
import 'http.dart' as http;
import 'parse.dart' as parse;

/// 获取当前登录用户状态
///
/// 返回包含 uid / username / avatarUrl / credits / userGroup 等的 Map。
/// 若未登录，返回 {success: false, uid: '0'}。
Future<Map<String, dynamic>> fetch(Dio dio) async {
  final resp = await http.getUserStatus(dio);
  return parse.parseResponse(safeDecode(resp), resp.statusCode ?? 0);
}
