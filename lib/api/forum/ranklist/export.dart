import 'package:dio/dio.dart';
import '../../helpers.dart';
import 'http.dart' as http;
import 'parse.dart' as parse;

/// 获取帖子排行榜
///
/// [view] 可选值：replies（回复）, views（查看）, heats（热度）, sharetimes（分享）, favtimes（收藏）
/// [orderby] 可选值：thisweek（本周）, thismonth（本月）, today（今日）, all（全部）
Future<Map<String, dynamic>> getRanklist(Dio dio, {
  required String view,
  String orderby = 'thisweek',
}) async {
  final resp = await http.getRanklist(dio, view: view, orderby: orderby);
  return parse.parseResponse(safeDecode(resp), resp.statusCode ?? 0);
}
