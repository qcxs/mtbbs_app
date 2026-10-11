import 'package:mtbbs/api/helpers.dart';

/// 版块帖子列表响应解析（与导读共用 [parseThreadListPage]）
///
/// 从完整 HTML 页面中提取帖子列表和分页信息，复用 thread_parser 解析帖子列表。
Map<String, dynamic> parseResponse(String body, int statusCode) =>
    parseThreadListPage(body, statusCode);
