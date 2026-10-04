import 'package:dio/dio.dart';
import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/api/group/groupindex/http.dart' as http;
import 'package:mtbbs/api/group/groupindex/parse.dart' as parse;

/// 获取圈子首页（推荐圈子 + 圈子分类 + 积分排行）
Future<Map<String, dynamic>> fetchGroupIndex(Dio dio) async {
  final resp = await http.getGroupIndex(dio);
  return parseWithLog(resp, parse.parseIndex);
}

/// 获取某个圈子分类下的圈子列表（分页）
Future<Map<String, dynamic>> fetchCategoryGroups(
  Dio dio, {
  required String gid,
  int page = 1,
}) async {
  final resp = await http.getCategoryGroups(dio, gid: gid, page: page);
  return parseWithLog(resp, parse.parseCategoryGroups);
}
