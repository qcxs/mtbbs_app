import 'package:dio/dio.dart';
import '../../helpers.dart';
import '../../../core/url_util.dart';
import 'http.dart' as http;
import 'parse.dart' as parse;

/// 获取 RSS 订阅列表
///
/// 自动将 RSS 中的相对链接归一化为绝对 URL（基于当前站点 baseUrl）。
Future<Map<String, dynamic>> getRssFeed(Dio dio) async {
  final resp = await http.getRssFeed(dio);
  final result = parse.parseResponse(safeDecode(resp), resp.statusCode ?? 0);
  if (result['success'] == true && result['items'] != null) {
    final items = result['items'] as List<dynamic>;
    for (final item in items) {
      if (item is Map<String, dynamic> && item['link'] != null) {
        item['link'] = normalizeUrl(item['link'].toString());
      }
    }
  }
  return result;
}
