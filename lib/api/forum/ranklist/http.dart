import 'package:dio/dio.dart';
import '../../../config/site_config.dart';

/// 帖子排行榜 HTTP 请求
///
/// type=thread, view=replies|views|heats|sharetimes|favtimes, orderby=thisweek|thismonth|today|all
/// 必须使用 PC User-Agent，部分站点会因 UA 不同返回不同模板（移动端非 table 结构）。
/// baseUrl 由 Dio 实例的 BaseOptions 提供。
Future<Response<String>> getRanklist(
  Dio dio, {
  required String view,
  String orderby = 'thisweek',
}) {
  return dio.get<String>(
    '/misc.php?mod=ranklist&type=thread&view=$view&orderby=$orderby&inajax=1',
    options: Options(
      headers: {
        'User-Agent': Site.uaPc,
        'X-Requested-With': 'XMLHttpRequest',
      },
    ),
  );
}
