import 'package:dio/dio.dart';
import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/api/forum/viewthread/viewpid/http.dart' as http;
import 'package:mtbbs/api/forum/viewthread/viewpid/parse.dart' as parse;
import 'package:mtbbs/core/utils/logger.dart';

/// 获取单帖详情（表情还原由解析层自行从 EmojiService 读取当前站点数据）。
Future<Map<String, dynamic>> getPostByPid(
  Dio dio, {
  required String tid,
  required String viewpid,
}) async {
  final resp = await http.getPostByPid(dio, tid: tid, viewpid: viewpid);
  return parseWithLog(resp, parse.parseResponse);
}

/// 解析「按 pid 定位回复」链接对应的 tid（供 App 内帖子页定位）。
///
/// Discuz 的 `forum.php?mod=redirect&goto=findpost&pid=X` 会 301 到含 `tid` 的
/// 帖子地址；本函数只取该 301 的 `Location` 并解析出 tid（不下载整页帖子）。
/// 解析失败返回 `{success: false}`，调用方退回内置浏览器即可。
Future<Map<String, dynamic>> resolveTidByPid(
  Dio dio, {
  required String pid,
}) async {
  try {
    final resp = await http.getFindpostRedirect(dio, pid: pid);
    final location = resp.headers.value('location') ?? '';
    final result = parse.parseFindpostLocation(
      location,
      resp.statusCode ?? 0,
    );
    if (result['success'] == true) {
      AppLogger.i(
        'PARSE',
        'findpost pid=$pid → tid=${result['tid']} page=${result['page']}',
      );
    }
    return result;
  } catch (e) {
    AppLogger.w('PARSE', 'resolveTidByPid(pid=$pid) error: $e');
    return {'success': false, 'message': '解析失败: $e'};
  }
}
