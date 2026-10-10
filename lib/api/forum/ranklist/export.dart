import 'package:dio/dio.dart';
import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/api/forum/ranklist/http.dart' as http;
import 'package:mtbbs/api/forum/ranklist/parse.dart' as parse;

/// 排行榜统一入口 —— 按 [type] 分发到对应解析器。
///
/// [type] : `thread`（帖子）| `member`（用户）| `forum`（版块）
/// [view] : 各类型视图，见 `parse.dart` 各解析器注释
/// [orderby] : 仅 `thread` 有效（thisweek|thismonth|today|all）
Future<Map<String, dynamic>> getRanklist(
  Dio dio, {
  required String type,
  required String view,
  String? orderby,
}) async {
  final resp = await http.getRanklist(
    dio,
    type: type,
    view: view,
    orderby: orderby,
  );
  return parseWithLog(
    resp,
    (b, s) => switch (type) {
      'member' => parse.parseMemberResponse(b, s),
      'forum' => parse.parseForumResponse(b, s),
      _ => parse.parseThreadResponse(b, s),
    },
  );
}

/// 帖子排行（type=thread）
///
/// [view] : replies（回复）| views（查看）| sharetimes（分享）| favtimes（收藏）| heats（热度）
/// [orderby] : thisweek（本周）| thismonth（本月）| today（今日）| all（全部）
Future<Map<String, dynamic>> getThreadRanklist(
  Dio dio, {
  required String view,
  String orderby = 'thisweek',
}) => getRanklist(dio, type: 'thread', view: view, orderby: orderby);

/// 用户排行（type=member）
///
/// [view] : beauty（美女）| handsome（帅哥）| credit（积分）| friendnum（好友数）|
///          invite（邀请）| post（发帖数）| onlinetime（在线时间）
Future<Map<String, dynamic>> getMemberRanklist(
  Dio dio, {
  required String view,
}) => getRanklist(dio, type: 'member', view: view);

/// 版块排行（type=forum）
///
/// [view] : threads（发帖）| posts（回复）| today（最近 24 小时发帖）
Future<Map<String, dynamic>> getForumRanklist(
  Dio dio, {
  required String view,
}) => getRanklist(dio, type: 'forum', view: view);
