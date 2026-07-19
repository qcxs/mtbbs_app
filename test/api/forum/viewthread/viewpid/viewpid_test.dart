import 'dart:io';

import 'package:dio/dio.dart';

import 'export.dart' as viewpid;

/// 单帖详情（viewpid）API 测试
///
/// 用法:
///   dart run lib/api/forum/viewthread/viewpid/test.dart --tid=161119 --viewpid=10629341
///   dart run lib/api/forum/viewthread/viewpid/test.dart --tid=161119 --viewpid=10629341 --base-url=http://localhost
void main(List<String> args) async {
  final tid = _parseArg(args, '--tid');
  final viewpidParam = _parseArg(args, '--viewpid');
  final baseUrl = _parseArg(args, '--base-url') ?? 'https://bbs.binmt.cc';

  if (tid == null || viewpidParam == null) {
    stderr.writeln(
      '用法: dart run lib/api/forum/viewthread/viewpid/test.dart --tid=161119 --viewpid=10629341',
    );
    exit(1);
  }

  print('========== 单帖详情 API 测试 ==========');
  print('tid: $tid, viewpid: $viewpidParam');
  print('baseUrl: $baseUrl\n');

  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36',
        'X-Requested-With': 'XMLHttpRequest',
      },
    ),
  );

  print('--- HTTP ---');
  final result = await viewpid.getPostByPid(
    dio,
    tid: tid,
    viewpid: viewpidParam,
  );
  _printResult(result);
}

String? _parseArg(List<String> args, String key) {
  for (final a in args) {
    if (a.startsWith('$key=')) return a.substring(key.length + 1);
  }
  return null;
}

void _printResult(Map<String, dynamic> result) {
  print('  success = ${result['success']}\n');

  if (result['success'] != true) {
    stderr.writeln('❌ 获取失败: ${result['message']}');
    exit(1);
  }

  final post = result['post'] as Map<String, dynamic>?;
  if (post == null) {
    stderr.writeln('❌ 未找到帖子数据');
    exit(1);
  }

  print('  PID:      ${post['pid']}');
  print('  用户名:   ${post['username']}');
  print('  UID:      ${post['uid']}');
  print('  时间:     ${post['postTime']}');
  print('  IP属地:   ${post['ipLocation']}');
  print('  楼层:     ${post['floorLabel']} (${post['floor']})');
  print('  用户组:   ${post['usergroup']}');
  final bbcode = post['bbcode'] as String? ?? '';
  print('  BBCode(${bbcode.length}):');
  final preview =
      bbcode.length > 300 ? '${bbcode.substring(0, 300)}...' : bbcode;
  for (final line in preview.split('\n')) {
    print('    | $line');
  }

  print('\n✅ 测试通过');
}
