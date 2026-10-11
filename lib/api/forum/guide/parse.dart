import 'package:mtbbs/api/helpers.dart';

/// 导读响应解析（与版块列表共用 [parseThreadListPage]）
Map<String, dynamic> parseResponse(String body, int statusCode) =>
    parseThreadListPage(body, statusCode);
