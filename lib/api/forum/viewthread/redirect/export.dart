import 'package:dio/dio.dart';
import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/api/forum/viewthread/redirect/http.dart' as http;
import 'package:mtbbs/api/forum/viewthread/redirect/parse.dart' as parse;
import 'package:mtbbs/core/utils/logger.dart';

/// 解析 Discuz 跳转定位接口的最终落点（楼层页 / 回复页）。
///
/// 返回 `{success, tid, page, pid, authorid}`；失败时带 `reason`：
/// - `no_redirect`：主题不存在 / 未落到帖子页（含 WAF 未通过）
/// - `floor_not_found`：落到帖子页但没有页码（楼层超出范围）
Future<Map<String, dynamic>> resolveRedirectPage(
  Dio dio, {
  String? tid,
  int? postno,
  String? authorid,
  String? pid,
}) async {
  try {
    final resp = await http.getRedirect(
      dio,
      tid: tid,
      postno: postno,
      authorid: authorid,
      pid: pid,
    );
    return parseWithLog(resp, (_, status) {
      final locations = resp.redirects
          .map((r) => r.location.toString())
          .toList(growable: false);
      return parse.parseRedirectLocations(locations, status);
    });
  } catch (e) {
    AppLogger.w('PARSE', 'resolveRedirectPage error: $e');
    return {'success': false, 'reason': 'no_redirect', 'message': '解析失败: $e'};
  }
}
