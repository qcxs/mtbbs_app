import 'package:dio/dio.dart';

/// 排行榜 HTTP 请求（统一入口）
///
/// [type] 排行维度：
/// - `thread` 帖子排行 —— view=replies|views|sharetimes|favtimes|heats，
///   orderby=thisweek|thismonth|today|all
/// - `member` 用户排行 —— view=beauty|handsome|credit|friendnum|invite|post|onlinetime
/// - `forum`  版块排行 —— view=threads|posts|today
///
/// [orderby] 仅 `type=thread` 有效，其余类型忽略。
///
/// 响应统一为 `<root><![CDATA[…PC 模板 HTML…]]></root>`（`inajax=1`）。
/// 依赖 ApiService 统一注入的 PC User-Agent —— Discuz 按 UA 返回不同模板，
/// 三类解析器都按 PC 模板结构编写（`parse.dart`）。
Future<Response<String>> getRanklist(
  Dio dio, {
  required String type,
  required String view,
  String? orderby,
}) {
  final ob = (orderby == null || orderby.isEmpty) ? '' : '&orderby=$orderby';
  return dio.get<String>(
    '/misc.php?mod=ranklist&type=$type&view=$view$ob&inajax=1',
  );
}
