import 'dart:io';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as htmlParser;
import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/core/page_helper.dart';

import 'export.dart' as forumdisplay;

/// 版块帖子列表 API 测试
///
/// 覆盖全流程：HTTP → checkPageError → parseThreadList → Json
/// 用法:
///   dart run lib/api/forum/forumdisplay/test.dart --fid=37
///   dart run lib/api/forum/forumdisplay/test.dart --fid=37 --page=2
///   dart run lib/api/forum/forumdisplay/test.dart --fid=37 --base-url=http://localhost
void main(List<String> args) async {
  // 模拟 App 初始化：设置默认站点
  SiteConfig.init();

  final fid = _parseArg(args, '--fid');
  final page = int.tryParse(_parseArg(args, '--page') ?? '1') ?? 1;
  final baseUrl = _parseArg(args, '--base-url') ?? 'https://bbs.binmt.cc';

  if (fid == null) {
    stderr.writeln('❌ 请指定 --fid（版块 ID）');
    stderr.writeln(
      '用法: dart run lib/api/forum/forumdisplay/test.dart --fid=37',
    );
    exit(1);
  }

  await _testHttp(fid, page, baseUrl);
}

String? _parseArg(List<String> args, String key) {
  for (final a in args) {
    if (a.startsWith('$key=')) return a.substring(key.length + 1);
  }
  return null;
}

Future<void> _testHttp(String fid, int page, String baseUrl) async {
  print('========== 版块帖子列表 API 测试 ==========');
  print('fid: $fid, page: $page');
  print('baseUrl: $baseUrl\n');

  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36',
      },
    ),
  );

  // === Step 1: 发送 HTTP 请求 ===
  print('--- Step 1: HTTP ---');
  final resp = await dio.get<String>(
    '/forum.php?mod=forumdisplay&fid=$fid&page=$page&mobile=2',
  );
  final body = resp.data ?? '';
  print('  statusCode  = ${resp.statusCode}');
  print('  body.length = ${body.length}\n');

  // === Step 2: checkPageError 检测 ===
  print('--- Step 2: checkPageError ---');
  final doc = htmlParser.parse(body);
  final pageError = checkPageError(doc, body);
  print('  isError       = ${pageError.isError}');
  print('  loginRequired = ${pageError.loginRequired}');
  print('  message       = ${pageError.message}');
  if (pageError.isError) {
    stderr.writeln('\n❌ checkPageError 误判为错误页');
    stderr.writeln('   消息: ${pageError.message}');
    exit(1);
  }
  print('  ✅ 通过\n');

  // === Step 3: 完整 parse 流程 ===
  print('--- Step 3: 完整 parse ---');
  final result = await forumdisplay.getForumThreads(dio, fid: fid, page: page);
  _printResult(result);
}

void _printResult(Map<String, dynamic> result) {
  print('  success      = ${result['success']}');
  print('  count        = ${result['count']}');
  print('  currentPage  = ${result['currentPage']}');
  print('  totalPages   = ${result['totalPages']}\n');

  if (result['success'] != true) {
    stderr.writeln('❌ ${result['message']}');
    exit(1);
  }

  final threads = result['threads'] as List<dynamic>? ?? [];
  for (int i = 0; i < threads.length && i < 5; i++) {
    final t = threads[i] as Map<String, dynamic>;
    print('--- [${i + 1}] ---');
    print('  ${t['nickname'] ?? '?'}  ${t['time'] ?? ''}');
    print('  ${t['title'] ?? ''}');
    print('');
  }

  if (threads.length > 5) {
    print('  ... 还有 ${threads.length - 5} 条');
  }

  print('✅ 测试通过\n');
}
