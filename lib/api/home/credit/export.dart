import 'package:dio/dio.dart';
import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/api/home/credit/http.dart' as http;
import 'package:mtbbs/api/home/credit/parse.dart' as parse;

/// 积分公式 API 导出

Future<Map<String, dynamic>> fetch(Dio dio) async {
  final resp = await http.getCreditFormula(dio);
  return parseWithLog(resp, parse.parseResponse);
}

/// 积分记录（需登录）—— 仅当前登录用户的积分变更记录
///
/// [exttype]：`0`=不限 / `1`=好评 / `2`=金币 / `3`=信誉；
/// [income]：`0`=不限 / `1`=收入 / `-1`=支出；
/// [optype]：操作类型（如 `PRC`=帖子被评分，空=不限）。
Future<Map<String, dynamic>> fetchCreditLog(
  Dio dio, {
  int page = 1,
  String exttype = '0',
  String income = '0',
  String optype = '',
  String starttime = '',
  String endtime = '',
}) async {
  final resp = await http.getCreditLog(
    dio,
    page: page,
    exttype: exttype,
    income: income,
    optype: optype,
    starttime: starttime,
    endtime: endtime,
  );
  return parseWithLog(resp, parse.parseLogResponse);
}
