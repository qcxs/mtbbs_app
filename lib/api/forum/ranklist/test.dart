import 'dart:io';
import 'package:dio/dio.dart';
import 'export.dart' as api;

/// 测试帖子排行榜 API
///
/// 用法：
///   dart run lib/api/forum/ranklist/test.dart
///   dart run lib/api/forum/ranklist/test.dart --view=views
///   dart run lib/api/forum/ranklist/test.dart --view=replies --orderby=thisweek
void main(List<String> args) async {
  String view = 'replies';
  String orderby = 'thisweek';

  for (int i = 0; i < args.length; i++) {
    if (args[i].startsWith('--view=')) view = args[i].substring(7);
    if (args[i].startsWith('--orderby=')) orderby = args[i].substring(10);
  }

  final dio = Dio(BaseOptions(
    baseUrl: 'https://bbs.binmt.cc',
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    },
  ));

  final result = await api.getRanklist(dio, view: view, orderby: orderby);

  if (result['success'] != true) {
    stderr.writeln('Error: ${result['message']}');
    exit(1);
  }

  final items = result['items'] as List<dynamic>;
  print('Ranklist: view=$view, orderby=$orderby, ${items.length} items\n');

  for (final item in items) {
    final m = item as Map<String, dynamic>;
    print('#${m['rank']} ${m['title']}');
    print('   ${m['forumName']} | ${m['author']} | ${m['time']}');
    print('   count=${m['count']} | tid=${m['tid']}');
    print('');
  }

  print('Done.');
}
