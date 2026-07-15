import 'dart:io';

import 'package:dio/dio.dart';

import 'export.dart' as credit_api;
import 'package:mtbbs/config/site_config.dart';

/// 积分公式 API 测试
///
/// 用法:
///   dart run lib/api/home/credit/test.dart
///   dart run lib/api/home/credit/test.dart --http
///   dart run lib/api/home/credit/test.dart --base-url=http://localhost
void main(List<String> args) async {
  final baseUrl = _parseArg(args, '--base-url') ?? 'https://bbs.binmt.cc';
  final onlyHttp = args.contains('--http');

  if (onlyHttp) {
    await _testHttp(baseUrl);
  } else {
    await _testFull(baseUrl);
  }
}

String? _parseArg(List<String> args, String key) {
  for (final a in args) {
    if (a.startsWith('$key=')) return a.substring(key.length + 1);
  }
  return null;
}

Future<void> _testHttp(String baseUrl) async {
  print('========== 积分公式 HTTP 测试 ==========');
  print('baseUrl: $baseUrl\n');

  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      headers: {'User-Agent': SiteConfig.uaAndroid},
    ),
  );

  print('--- HTTP 原始响应 ---');
  final resp = await dio.get<String>('/home.php?mod=spacecp&ac=credit');
  print(resp.data ?? '(empty)');
}

Future<void> _testFull(String baseUrl) async {
  print('========== 积分公式 API 测试 ==========');
  print('baseUrl: $baseUrl\n');

  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      headers: {'User-Agent': SiteConfig.uaAndroid},
    ),
  );

  print('--- 调用 fetch ---');
  final result = await credit_api.fetch(dio);
  _printResult(result);
}

void _printResult(Map<String, dynamic> result) {
  print('  success = ${result['success']}\n');

  if (result['success'] != true) {
    stderr.writeln('❌ ${result['message']}');
    exit(1);
  }

  print('  当前积分: ${result['credits'] ?? '?'}\n');

  print('--- 积分公式 ---');
  print('  ${result['formula'] ?? '无'}');

  final items = result['items'] as List<dynamic>?;
  if (items != null && items.isNotEmpty) {
    print('\n--- 积分明细 ---');
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      print('  ${m['label']}: ${m['value']}');
    }
  }

  print('\n✅ 测试通过\n');
}
