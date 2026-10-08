import 'package:dio/dio.dart';
import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/api/site/cdn/http.dart' as http;
import 'package:mtbbs/api/site/cdn/parse.dart' as parse;
import 'package:mtbbs/core/utils/logger.dart';

/// 探测当前站点实际使用的 CDN
///
/// 依次请求 [http.kCdnProbePath] → [http.kCdnProbeFallbackPath]，取第一个能从
/// 页面里解析出 `STATICURL` 的结果。两者都失败时返回 `{success:false}`，
/// 由调用方回退到站点 [baseUrl]（不抛异常、不影响启动）。
Future<Map<String, dynamic>> fetchSiteCdn(Dio dio) async {
  for (final path in [http.kCdnProbePath, http.kCdnProbeFallbackPath]) {
    try {
      final resp = await http.fetchCdnPage(dio, path);
      final result = parseWithLog(resp, parse.parseResponse);
      if (result['success'] == true) return result;
    } catch (e) {
      AppLogger.w('PARSE', 'CDN 探测 $path 失败: $e');
    }
  }
  return {'success': false, 'message': '未能识别站点 CDN'};
}
