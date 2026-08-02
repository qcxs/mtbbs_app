import 'package:dio/dio.dart';
import 'package:mtbbs/api/helpers.dart';
import 'http.dart' as http;
import 'parse.dart' as parse;

/// 收藏 API 导出

Future<Map<String, dynamic>> fetchFavorites(Dio dio, {int page = 1}) async {
  final resp = await http.getFavorites(dio, page: page);
  return parseWithLog(resp, parse.parseResponse);
}

/// 收藏帖子（写操作，带备注）
///
/// 联动：先 GET 帖子页提取全局 formhash（Discuz CSRF 令牌），
/// 再 POST 收藏。备注通过 description 字段写入（手机端表单学习）。
Future<Map<String, dynamic>> addFavorite(
  Dio dio, {
  required String tid,
  String? note,
}) async {
  // 1. GET 帖子页提取 formhash（与删除收藏同理，联动提取）
  final threadResp = await dio.get<String>(
    '/forum.php?mod=viewthread&tid=$tid',
  );
  final formhash =
      RegExp(
        r'name="formhash"\s+value="([^"]+)"',
      ).firstMatch(threadResp.data ?? '')?.group(1) ??
      '';
  if (formhash.isEmpty) {
    return {'success': false, 'message': '未提取到 formhash（可能未登录）'};
  }

  // 2. POST 收藏（带备注）
  final resp = await http.addFavorite(
    dio,
    tid: tid,
    formhash: formhash,
    note: note,
  );
  return parseWithLog(resp, parse.parseAddResult);
}

/// 删除收藏（写操作）
///
/// 联动：先 GET 收藏列表页提取全局 formhash（Discuz CSRF 令牌），
/// 再 POST 删除。调用方只需提供 favid。
Future<Map<String, dynamic>> deleteFavorite(
  Dio dio, {
  required String favid,
}) async {
  // 1. GET 收藏列表页提取 formhash（每页都有全局隐藏 input）
  final listResp = await http.getFavorites(dio, page: 1);
  final formhash =
      RegExp(
        r'name="formhash"\s+value="([^"]+)"',
      ).firstMatch(listResp.data ?? '')?.group(1) ??
      '';
  if (formhash.isEmpty) {
    return {'success': false, 'message': '未提取到 formhash（可能未登录）'};
  }

  // 2. POST 删除
  final resp = await http.deleteFavorite(dio, favid: favid, formhash: formhash);
  return parseWithLog(resp, parse.parseDeleteResult);
}
