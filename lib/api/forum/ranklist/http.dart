import 'package:dio/dio.dart';

/// 帖子排行榜 HTTP 请求
///
/// type=thread, view=replies|views|heats|sharetimes|favtimes, orderby=thisweek|thismonth|today|all
/// 依赖 ApiService 统一注入的 PC User-Agent（部分站点会因 UA 不同返回不同模板）。
/// baseUrl 由 Dio 实例的 BaseOptions 提供。
Future<Response<String>> getRanklist(
  Dio dio, {
  required String view,
  String orderby = 'thisweek',
}) {
  return dio.get<String>(
    '/misc.php?mod=ranklist&type=thread&view=$view&orderby=$orderby&inajax=1',
  );
}
