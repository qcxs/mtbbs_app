import '../api/forum/ranklist/export.dart' as ranklist_api;
import 'api_service.dart';

/// 帖子排行榜 API — 委托给 lib/api/forum/ranklist/
class RanklistApi {
  /// 获取帖子排行榜
  ///
  /// [view] 可选值：replies（回复）, views（查看）, heats（热度）, sharetimes（分享）, favtimes（收藏）
  /// [orderby] 可选值：thisweek（本周）, thismonth（本月）, today（今日）, all（全部）
  static Future<Map<String, dynamic>> fetch({
    required String view,
    String orderby = 'thisweek',
  }) async {
    final dio = ApiService().dio;
    return ranklist_api.getRanklist(dio, view: view, orderby: orderby);
  }
}
