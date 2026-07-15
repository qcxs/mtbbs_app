import 'package:dio/dio.dart';
import '../../helpers.dart';
import 'http.dart';
import 'parse.dart';

/// 独立 CLI 测试
///
/// 用法：
/// ```bash
/// dart run lib/api/forum/rss/test.dart
/// ```
void main() async {
  final dio = Dio(BaseOptions(
    baseUrl: 'https://bbs.binmt.cc',
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36',
    },
  ));

  print('=== Step 1: HTTP ===');
  final resp = await getRssFeed(dio);
  final body = safeDecode(resp);
  print('status: ${resp.statusCode}');
  print('body length: ${body.length}');

  if (body.length > 200) {
    print('preview: ${body.substring(0, 200)}');
  }

  print('\n=== Step 2: Parse ===');
  final result = parseResponse(body, resp.statusCode ?? 0);
  print('success: ${result['success']}');
  if (result['success'] == true) {
    print('channel: ${result['channelTitle']}');
    final items = result['items'] as List<dynamic>;
    print('items: ${items.length}');
    for (final item in items.take(5)) {
      print('  - ${item['title']}');
      print('    link: ${item['link']}');
      if (item['pubDate'] != null) {
        print('    date: ${item['pubDate']}');
      }
    }
  } else {
    print('error: ${result['message']}');
  }
}
