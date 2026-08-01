import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/app/app_paths.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/services/api_service.dart';
import 'api_bootstrap.dart';
import 'api_scenarios.dart';

/// API 只读探针入口（AI 以命令 + 参数调用）
///
/// 用法（flutter test 驱动，--dart-define 传参）：
/// ```powershell
/// flutter test tool/api_probe_test.dart --dart-define=cmd=guide.list `
///   --dart-define=view=newthread --dart-define=page=1 --dart-define=log=info
/// ```
///
/// 参数：
///   cmd       场景命令（默认 session.list），见 [scenarios]
///   account   登录账号名（可空=游客），需先运行 App 登录生成 Cookie
///   site      站点（索引数字或站点名，空=默认第一个站点）
///   log       off/info/debug（默认 info，debug 输出 PARSE 明细）
///   其余键    透传给场景的 params
///
/// 输出协议（AI 机器可解析）：
/// ```
/// === API_PROBE_BEGIN ===
/// {json}
/// === API_PROBE_END ===
/// ```
/// ok=true 表示管线无异常；result 内 success 表示业务层结果；
/// 缺登录态时 blocked=true + reminder 提示先运行 App。
void main() {
  test('api-probe', () async {
    final cmd = const String.fromEnvironment(
      'cmd',
      defaultValue: 'session.list',
    );
    final account = const String.fromEnvironment('account', defaultValue: '');
    final site = const String.fromEnvironment('site', defaultValue: '');
    final log = const String.fromEnvironment('log', defaultValue: 'info');

    // 日志级别控制
    if (log == 'off') {
      AppLogger.enabled = false;
    } else if (log == 'debug') {
      AppLogger.level = LogLevel.debug;
    }

    // 注意：String.fromEnvironment 只在编译期常量表达式下生效，
    // 必须逐键显式 const 读取（循环变量运行时求值会取到默认值）。
    final args = <String, String>{
      'view': const String.fromEnvironment('view'),
      'page': const String.fromEnvironment('page'),
      'fid': const String.fromEnvironment('fid'),
      'orderby': const String.fromEnvironment('orderby'),
      'filter': const String.fromEnvironment('filter'),
      'tid': const String.fromEnvironment('tid'),
      'authorid': const String.fromEnvironment('authorid'),
      'uid': const String.fromEnvironment('uid'),
      'username': const String.fromEnvironment('username'),
      'type': const String.fromEnvironment('type'),
      // debug.http 专用：path=请求路径；q=额外 query 参数（JSON 字符串）
      'path': const String.fromEnvironment('path'),
      'n': const String.fromEnvironment('n'),
      'q': const String.fromEnvironment('q'),
    };

    final output = await runProbe(
      cmd: cmd,
      args: args,
      account: account,
      site: site,
    );

    print('=== API_PROBE_BEGIN ===');
    print(jsonEncode(output));
    print('=== API_PROBE_END ===');
    if (output['ok'] != true) {
      throw StateError('probe failed: ${output['error']}');
    }
  });
}

Future<Map<String, dynamic>> runProbe({
  required String cmd,
  required Map<String, String> args,
  required String account,
  String site = '',
}) async {
  // 自描述：无上下文的 AI 跑 help 即可掌握全部用法，无需读源码
  if (cmd == 'help' || cmd == '--help' || cmd == 'h') {
    return _buildHelp();
  }

  final scenario = scenarios[cmd];
  if (scenario == null) {
    return {
      'ok': true,
      'cmd': cmd,
      'result': {
        'success': false,
        'message': '未知命令 $cmd，可用：${scenarios.keys.join(', ')}',
      },
    };
  }

  try {
    await bootstrap(account: account, site: site);
  } catch (e) {
    return {'ok': false, 'cmd': cmd, 'error': '初始化失败: $e'};
  }

  final sw = Stopwatch()..start();
  try {
    // 需要登录的命令：先检查本机 Cookie，缺失则提示先运行 App
    if (scenario.needsLogin) {
      final cookieInfo = await _scanCookieDir();
      if (!(cookieInfo['hasAnyCookie'] as bool? ?? false)) {
        final host = SiteStore.instance.host;
        final dir = await AppPaths.cookiesDirForHost(host);
        return {
          'ok': true,
          'cmd': cmd,
          'blocked': true,
          'reminder':
              '未检测到 Cookie（$dir）。请先运行一次 App（flutter run -d windows）'
              '并登录（会生成 Cookie），退出后重试本命令；'
              '也可先用 cmd=session.list 确认本机登录状态。',
        };
      }
      if (account.isEmpty && (cookieInfo['guestCookies'] as int? ?? 0) == 0) {
        final names = (cookieInfo['accounts'] as List)
            .map((e) => (e as Map)['name'])
            .join(', ');
        return {
          'ok': true,
          'cmd': cmd,
          'blocked': true,
          'reminder':
              '该命令需要登录，但当前为游客态。可用账号: $names '
              '（追加 --dart-define=account=<账号名> 重试）。',
        };
      }
    }

    // 必填参数校验
    final missing = scenario.params.keys
        .where(
          (k) => scenario.params[k]!.startsWith('*') && (args[k] ?? '').isEmpty,
        )
        .toList();
    if (missing.isNotEmpty) {
      return {
        'ok': true,
        'cmd': cmd,
        'result': {
          'success': false,
          'message': '缺少必填参数: ${missing.join(', ')}',
        },
        'usage': scenario.desc,
      };
    }

    final result = await scenario.run(args);
    return {
      'ok': true,
      'cmd': cmd,
      'params': {
        for (final k in scenario.params.keys)
          if (args[k]?.isNotEmpty ?? false) k: args[k],
      },
      'runtimeMs': sw.elapsedMilliseconds,
      'account': ApiService().activeAccount ?? '(游客)',
      'result': compactJson(result, maxStr: scenario.raw ? 100000 : 160),
      'usage': scenario.desc,
    };
  } catch (e) {
    return {
      'ok': false,
      'cmd': cmd,
      'error': '$e',
      'runtimeMs': sw.elapsedMilliseconds,
    };
  }
}

/// 生成完整使用说明（自描述，无需读源码即可上手）
Map<String, dynamic> _buildHelp() {
  return {
    'ok': true,
    'cmd': 'help',
    'what': 'API 只读探针：真实请求 + 解析管线，复用 App 的 Cookie 登录态',
    'invoke': [
      r'flutter test tool/api_probe_test.dart --dart-define=cmd=<命令> --dart-define=key=value',
      r'跨平台通用，无 shell 依赖；帮助见 docs/10-API探针使用规范.md',
    ],
    'globalParams': {
      'cmd': '场景命令（默认 session.list），见下方 scenarios',
      'account': '登录账号名（空=游客）；先跑 session.list 查看可用账号',
      'site': '站点（索引或名称，空=第一个站点），如 site=1',
      'log': 'off/info/debug（默认 info，off 只输出协议 JSON）',
    },
    'scenarios': {
      for (final e in scenarios.entries)
        e.key: {
          'desc': e.value.desc,
          'params': e.value.params,
          'needsLogin': e.value.needsLogin,
        },
    },
    'examples': [
      r'flutter test tool/api_probe_test.dart --dart-define=cmd=session.list                    # 查看本机 Cookie/账号',
      r'flutter test tool/api_probe_test.dart --dart-define=cmd=guide.list --dart-define=view=newthread       # 导读（游客）',
      r'flutter test tool/api_probe_test.dart --dart-define=cmd=session.status --dart-define=account=青春向上 # 验证登录态',
      r'flutter test tool/api_probe_test.dart --dart-define=cmd=thread.detail --dart-define=tid=170313        # 帖子详情',
      r'flutter test tool/api_probe_test.dart --dart-define=cmd=debug.http --dart-define=path=/forum.php --dart-define=q=mod=guide,index=1',
      r'flutter test tool/api_probe_test.dart --dart-define=cmd=session.status --dart-define=site=1 --dart-define=account=qcxs  # 跨站点账号',
    ],
    'tips': [
      '首次使用：先运行一次 App（flutter run -d windows）并登录，生成 Cookie；'
          '或先跑 cmd=session.list 确认本机登录状态',
      '需要登录的命令返回 blocked=true 时，追加 account=<账号名> 重试',
      'debug.http 的额外 query 参数用 q=k1=v1,k2=v2 逗号分隔'
          '（URL 中的 & 会被 PowerShell→cmd 拆散，禁止直接传完整 URL）',
      '参数值不要包含 & | ; " 空格 等特殊字符',
      '大列表结果自动截断为前 3 项 + __more__，长字符串截断 160 字符',
    ],
  };
}

/// 扫描本机 Cookie 目录（游客 Cookie 数 + 各账号）
Future<Map<String, dynamic>> _scanCookieDir() async {
  final scan = await scenarios['session.list']!.run(const {});
  return scan;
}

// ==================== 输出压缩（代表性数据） ====================

/// 将返回值规范化为 JSON 兼容结构（对象 → toJson）
Object? _normalize(Object? v) {
  if (v is Map) return v.map((k, val) => MapEntry('$k', _normalize(val)));
  if (v is List) return v.map(_normalize).toList();
  if (v is String || v is num || v is bool || v == null) return v;
  try {
    return _normalize((v as dynamic).toJson());
  } catch (_) {
    return '$v';
  }
}

/// 递归压缩大结果：列表只保留前 [maxList] 项，长字符串截断到 [maxStr] 字符
Object? compactJson(Object? v, {int maxList = 3, int maxStr = 160}) {
  v = _normalize(v);
  if (v is Map) {
    return v.map((k, val) => MapEntry('$k', compactJson(val)));
  }
  if (v is List) {
    final out = v.take(maxList).map((e) => compactJson(e)).toList();
    if (v.length > maxList) out.add({'__more__': v.length - maxList});
    return out;
  }
  if (v is String && v.length > maxStr) {
    return '${v.substring(0, maxStr)}…(+${v.length - maxStr}字符截断)';
  }
  return v;
}
