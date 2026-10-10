import 'package:dio/dio.dart';

/// 积分公式 HTTP 请求 — 基于 Dio
///
/// 需要已登录状态。Android UA 由 Dio 实例的 BaseOptions 提供。

/// 获取积分公式页面
Future<Response<String>> getCreditFormula(Dio dio) {
  return dio.get<String>('/home.php?mod=spacecp&ac=credit');
}

/// 获取积分记录页面（需登录）
///
/// `op=log` 为当前登录用户的积分变更记录，`page` 从最新一页 1 起算。
///
/// 筛选参数（对应页面查询表单，GET 无需 formhash）：
/// - [exttype] 积分类型：`0`=不限 / `1`=好评 / `2`=金币 / `3`=信誉
/// - [income] 收支：`0`=不限 / `1`=收入 / `-1`=支出
/// - [optype] 操作类型：如 `PRC`=帖子被评分 / `RSC`=帖子评分（空=不限）
/// - [starttime] / [endtime] 起始/结束日期（`YYYY-MM-DD`，可空）
Future<Response<String>> getCreditLog(
  Dio dio, {
  int page = 1,
  String exttype = '0',
  String income = '0',
  String optype = '',
  String starttime = '',
  String endtime = '',
}) {
  final params = <String, String>{
    'mod': 'spacecp',
    'ac': 'credit',
    'op': 'log',
    'page': '$page',
    'exttype': exttype,
    'income': income,
    if (optype.isNotEmpty) 'optype': optype,
    if (starttime.isNotEmpty) 'starttime': starttime,
    if (endtime.isNotEmpty) 'endtime': endtime,
  };
  final qs = params.entries
      .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');
  return dio.get<String>('/home.php?$qs');
}
