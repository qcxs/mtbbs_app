import 'dart:io';
import 'package:dio/dio.dart';
import 'export.dart' as userstatus;
import '../../../config/site_config.dart';

/// 用户状态 API 测试
///
/// 需要登录态。
/// 用法:
///   dart run lib/api/misc/userstatus/test.dart
///   dart run lib/api/misc/userstatus/test.dart --http
void main(List<String> args) async {
  final baseUrl = _parseArg(args, '--base-url') ?? SiteConfig.baseUrl;

  if (args.contains('--http')) {
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
  final dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    headers: {'User-Agent': SiteConfig.uaAndroid},
  ));
  final resp = await dio.get<String>('/misc.php?mod=userstatus');
  print(resp.data ?? '(empty)');
}

Future<void> _testFull(String baseUrl) async {
  print('========== 用户状态 API 测试 ==========');
  print('baseUrl: $baseUrl\n');

  final dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    headers: {'User-Agent': SiteConfig.uaAndroid},
  ));

  final result = await userstatus.fetch(dio);
  print('  success   = ${result['success']}');
  print('  uid       = ${result['uid']}');
  print('  username  = ${result['username']}');
  print('  avatarUrl = ${result['avatarUrl']}');
  print('  spaceUrl  = ${result['spaceUrl']}');
  print('  credits   = ${result['credits']}');
  print('  userGroup = ${result['userGroup']}');

  if (result['success'] != true) {
    stderr.writeln('❌ ${result['message']}');
    exit(1);
  }

  print('\n✅ 测试通过\n');
}
