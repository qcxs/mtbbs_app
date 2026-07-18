import 'dart:io';

import 'package:dio/dio.dart';

import 'export.dart' as space;

/// 用户空间 API 测试
///
/// 用法:
///   dart run lib/api/home/space/test.dart --uid=152009
///   dart run lib/api/home/space/test.dart --username=admin
///   dart run lib/api/home/space/test.dart --uid=152009 --http
void main(List<String> args) async {
  final uid = _parseArg(args, '--uid');
  final username = _parseArg(args, '--username');
  if (uid == null && username == null) {
    stderr.writeln('请指定 --uid 或 --username 参数');
    stderr.writeln('用法: dart run lib/api/home/space/test.dart --uid=152009');
    stderr.writeln(
      '      dart run lib/api/home/space/test.dart --username=admin',
    );
    exit(1);
  }

  final baseUrl = _parseArg(args, '--base-url') ?? 'https://bbs.binmt.cc';
  final onlyHttp = args.contains('--http');
  final query = uid ?? username!;

  if (onlyHttp) {
    await _testHttp(query, baseUrl, isUsername: username != null);
  } else {
    await _testFull(query, baseUrl, isUsername: username != null);
  }
}

String? _parseArg(List<String> args, String key) {
  for (final a in args) {
    if (a.startsWith('$key=')) return a.substring(key.length + 1);
  }
  return null;
}

Future<void> _testHttp(
  String query,
  String baseUrl, {
  bool isUsername = false,
}) async {
  print('========== 用户空间 HTTP 测试 ==========');
  if (isUsername) {
    print('username: $query');
  } else {
    print('uid: $query');
  }
  print('baseUrl: $baseUrl\n');

  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      },
    ),
  );

  print('--- HTTP 原始响应 ---');
  final path = isUsername
      ? '/home.php?mod=space&username=${Uri.encodeComponent(query)}&do=profile'
      : '/home.php?mod=space&uid=$query&do=profile';
  final resp = await dio.get<String>(path);
  print(resp.data ?? '(empty)');
}

Future<void> _testFull(
  String query,
  String baseUrl, {
  bool isUsername = false,
}) async {
  print('========== 用户空间 API 测试 ==========');
  if (isUsername) {
    print('username: $query');
  } else {
    print('uid: $query');
  }
  print('baseUrl: $baseUrl\n');

  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      },
    ),
  );

  print('--- 调用 getUserProfile ---');
  final result = isUsername
      ? await space.getUserProfile(dio, username: query)
      : await space.getUserProfile(dio, uid: query);
  _printResult(result);
}

void _printResult(Map<String, dynamic> result) {
  print('  success = ${result['success']}\n');

  if (result['success'] != true) {
    stderr.writeln('❌ ${result['message']}');
    exit(1);
  }

  final profile = result['profile'] as Map<String, dynamic>?;
  if (profile == null) {
    stderr.writeln('❌ 无 profile 数据');
    exit(1);
  }

  print('--- 基本信息 ---');
  print('  uid         = ${profile['uid']}');
  print('  nickname    = ${profile['nickname']}');
  print('  avatar      = ${profile['avatar']}');
  print('  spaceUrl    = ${profile['spaceUrl']}');
  print('  online      = ${profile['online']}');
  print('  emailVerified = ${profile['emailVerified']}');
  print('  signature   = ${profile['signature']}');

  final stats = profile['stats'] as Map<String, dynamic>?;
  if (stats != null) {
    print('\n--- 统计概览 ---');
    stats.forEach((k, v) => print('  $k = $v'));
  }

  final details = profile['details'] as Map<String, dynamic>?;
  if (details != null) {
    print('\n--- 详细资料 ---');
    details.forEach((k, v) => print('  $k = $v'));
  }

  final activity = profile['activity'] as Map<String, dynamic>?;
  if (activity != null) {
    print('\n--- 活跃概况 ---');
    activity.forEach((k, v) => print('  $k = $v'));
  }

  final points = profile['points'] as Map<String, dynamic>?;
  if (points != null) {
    print('\n--- 积分统计 ---');
    points.forEach((k, v) => print('  $k = $v'));
  }

  final medals = profile['medals'] as List<dynamic>?;
  if (medals != null && medals.isNotEmpty) {
    print('\n--- 勋章 (${medals.length}) ---');
    for (final m in medals) {
      final medal = m as Map<String, dynamic>;
      print('  ${medal['name']}');
    }
  }

  print('\n✅ 测试通过\n');
}
