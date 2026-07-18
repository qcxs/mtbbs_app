import 'dart:io';

import 'package:dio/dio.dart';

import 'http.dart' as http;
import 'parse.dart' as parse;

/// 帖子详情 API 测试
///
/// 用法:
///   dart run lib/api/forum/viewthread/detail/test.dart --tid=161119
///   dart run lib/api/forum/viewthread/detail/test.dart --tid=161119 --http
///   dart run lib/api/forum/viewthread/detail/test.dart --parse
///   dart run lib/api/forum/viewthread/detail/test.dart --tid=161119 --base-url=http://localhost
///   dart run lib/api/forum/viewthread/detail/test.dart --tid=161119 --page=2
void main(List<String> args) async {
  final mode = _parseMode(args);
  final tid = _parseArg(args, '--tid') ?? _detectTidFromCache();
  final page = int.tryParse(_parseArg(args, '--page') ?? '1') ?? 1;
  final baseUrl = _parseArg(args, '--base-url') ?? 'https://bbs.binmt.cc';

  if (tid == null) {
    stderr.writeln('❌ 请指定 --tid（帖子 ID）');
    stderr.writeln(
      '用法: dart run lib/api/forum/viewthread/detail/test.dart --tid=161119',
    );
    exit(1);
  }

  switch (mode) {
    case 'http':
      await _testHttp(tid, page, baseUrl);
    case 'parse':
      await _testParse(tid);
    default:
      await _testFull(tid, page, baseUrl);
  }
}

// ============================================================
// 参数解析
// ============================================================

String _parseMode(List<String> args) {
  if (args.contains('--http')) return 'http';
  if (args.contains('--parse')) return 'parse';
  return 'full';
}

String? _parseArg(List<String> args, String key) {
  for (final a in args) {
    if (a.startsWith('$key=')) return a.substring(key.length + 1);
  }
  return null;
}

String? _detectTidFromCache() {
  final dir = Directory('lib/api/forum/viewthread/detail/raw');
  if (!dir.existsSync()) return null;
  final files = dir.listSync().whereType<File>().toList();
  if (files.isEmpty) return null;
  for (final f in files) {
    final m = RegExp(r'thread_(\d+)_').firstMatch(f.path);
    if (m != null) return m.group(1);
  }
  return null;
}

// ============================================================
// raw/ 管理
// ============================================================

String _rawFile(String tid) =>
    'lib/api/forum/viewthread/detail/raw/thread_${tid}_response.html';

Future<void> _saveRaw(String body, String tid) async {
  final dir = Directory('lib/api/forum/viewthread/detail/raw');
  if (!await dir.exists()) await dir.create(recursive: true);
  await File(_rawFile(tid)).writeAsString(body);
}

Future<String?> _loadRaw(String tid) async {
  final file = File(_rawFile(tid));
  if (!await file.exists()) return null;
  return await file.readAsString();
}

// ============================================================
// 测试模式
// ============================================================

Future<void> _testFull(String tid, int page, String baseUrl) async {
  print('========== 帖子详情 API 测试 ==========');
  print('模式: 完整流程');
  print('tid: $tid, page: $page');
  print('baseUrl: $baseUrl\n');

  final dio = Dio(BaseOptions(baseUrl: baseUrl));

  print('--- HTTP ---');
  final resp = await _doRequest(dio, tid, page);
  if (resp == null) exit(1);

  final body = resp.data ?? '';
  await _saveRaw(body, tid);
  print('  raw 已保存到 ${_rawFile(tid)}\n');

  print('--- 解析 ---');
  _printResult(body, resp.statusCode ?? 0);
}

Future<void> _testHttp(String tid, int page, String baseUrl) async {
  print('========== 帖子详情 API 测试 ==========');
  print('模式: 仅 HTTP');
  print('tid: $tid, page: $page');
  print('baseUrl: $baseUrl\n');

  final dio = Dio(BaseOptions(baseUrl: baseUrl));

  final resp = await _doRequest(dio, tid, page);
  if (resp == null) exit(1);

  final body = resp.data ?? '';
  await _saveRaw(body, tid);
  print('  raw 已保存到 ${_rawFile(tid)}\n');
  print('✅ HTTP 测试通过');
}

Future<void> _testParse(String tid) async {
  print('========== 帖子详情 API 测试 ==========');
  print('模式: 仅解析\n');

  final body = await _loadRaw(tid);
  if (body == null) {
    stderr.writeln('❌ 未找到缓存，请先运行完整模式或 --http');
    exit(1);
  }

  print('  数据来源: ${_rawFile(tid)}');
  print('  响应长度: ${body.length} 字节\n');
  _printResult(body, 200);
}

// ============================================================
// 通用
// ============================================================

Future<Response<String>?> _doRequest(Dio dio, String tid, int page) async {
  print('  GET /forum.php?mod=viewthread&tid=$tid&page=$page');

  final resp = await http.getThreadDetail(dio, tid: tid, page: page);
  print('  状态: ${resp.statusCode}');
  print('  Content-Type: ${resp.headers.value('content-type')}');

  if (resp.statusCode != 200) {
    print('  ❌ 请求失败');
    return null;
  }

  final body = resp.data ?? '';
  print(
    '  响应(前200): ${body.length > 200 ? '${body.substring(0, 200)}...' : body}',
  );
  print('  ✅ 请求成功');
  return resp;
}

void _printResult(String body, int statusCode) {
  final result = parse.parseResponse(body, statusCode);

  print('  success      = ${result['success']}');
  print('  tid          = ${result['tid']}');
  print('  title        = ${result['title']}');
  print('  currentPage  = ${result['currentPage']}');
  print('  totalPages   = ${result['totalPages']}');
  print('  count(评论)   = ${result['count']}\n');

  if (result['success'] != true) {
    print('\n❌ 解析失败: ${result['message']}');
    exit(1);
  }

  // 打印楼主
  final mainPost = result['mainPost'] as Map<String, dynamic>?;
  if (mainPost != null) {
    print('===== 楼主 =====');
    print('  PID:      ${mainPost['pid']}');
    print('  用户名:   ${mainPost['username']}');
    print('  UID:      ${mainPost['uid']}');
    print('  用户组:   ${mainPost['usergroup']}');
    print('  时间:     ${mainPost['postTime']}');
    print('  IP属地:   ${mainPost['ipLocation']}');
    print('  来源:     ${mainPost['source']}');
    print('  followUrl: ${mainPost['followUrl']}');
    final bbcode = mainPost['bbcode'] as String? ?? '';
    print('  BBCode(${bbcode.length}):');
    final preview = bbcode.length > 300
        ? '${bbcode.substring(0, 300)}...'
        : bbcode;
    for (final line in preview.split('\n')) {
      print('    | $line');
    }
    print('');
  } else {
    print('  (page>1，无楼主数据)\n');
  }

  // 打印评论
  final posts = result['posts'] as List<dynamic>? ?? [];
  print('===== 评论(${posts.length}条) =====');
  for (int i = 0; i < posts.length && i < 10; i++) {
    final p = posts[i] as Map<String, dynamic>;
    print('--- #${p['floor']} ---');
    print('  PID:      ${p['pid']}');
    print('  用户名:   ${p['username']}');
    print('  楼层标签:  ${p['floorLabel']}');
    print('  UID:      ${p['uid']}');
    print('  用户组:   ${p['usergroup']}');
    print('  时间:     ${p['postTime']}');
    print('  IP属地:   ${p['ipLocation']}');
    print('  来源:     ${p['source']}');
    final bbcode = p['bbcode'] as String? ?? '';
    print('  BBCode(${bbcode.length}):');
    final preview = bbcode.length > 200
        ? '${bbcode.substring(0, 200)}...'
        : bbcode;
    for (final line in preview.split('\n')) {
      print('    | $line');
    }
    print('');
  }

  if (posts.length > 10) {
    print('  ... 还有 ${posts.length - 10} 条');
  }

  print('✅ 解析测试通过');
}
