import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/app/app_paths.dart';
import 'package:mtbbs/core/app/browse_mode.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/services/api_service.dart';
import 'api_bootstrap.dart';
import 'api_scenarios.dart';
import 'scenarios/mcp_coverage.dart';

/// API 只读探针入口（AI 以命令 + 参数调用）
///
/// 用法（flutter test 驱动，--dart-define 传参）：
/// ```powershell
/// flutter test tool/api_probe_test.dart --dart-define=cmd=guide.list `
///   --dart-define=view=newthread --dart-define=page=1 --dart-define=log=info
/// ```
///
/// 参数：
///   argsFile  参数 JSON 文件路径（推荐；无白名单限制、免特殊字符转义）
///   maxList   结果列表保留项数（默认 3，上限 50）
///   maxStr    结果字符串截断长度（默认 160，上限 100000）
///   cmd       场景命令（默认 session.list），见 [scenarios]；cmd=coverage 查看覆盖矩阵
///   account   登录账号名（可空=游客），需先运行 App 登录生成 Cookie
///   site      站点（索引数字或站点名，空=默认第一个站点）
///   ua        临时换用浏览模式：mobile / desktop(或 pc)；空=跟随站点设置
///   log       off/info/debug（默认 info，debug 输出 PARSE 明细）
///   其余键    透传给场景的 params
///
/// 输出协议（AI 机器可解析）：
/// ```
/// === API_PROBE_BEGIN ===
/// {json}
/// === API_PROBE_END ===
/// ```
/// ok=true 表示管线无异常；status 细分为 ok/invalid_args/blocked/business/failed；
/// result 内 success 表示业务层结果；缺登录态时 blocked=true + reminder 提示先运行 App。
void main() {
  test('api-probe', () async {
    const argsFile = String.fromEnvironment('argsFile');
    Map<String, String> fileArgs = {};
    if (argsFile.isNotEmpty) {
      try {
        fileArgs = await _loadArgsFile(argsFile);
      } catch (e) {
        final output = {
          'ok': false,
          'status': 'failed',
          'cmd': '<argsFile>',
          'error': 'argsFile 读取失败: $e',
        };
        print('=== API_PROBE_BEGIN ===');
        print(jsonEncode(output));
        print('=== API_PROBE_END ===');
        throw StateError('probe failed: ${output['error']}');
      }
    }

    // 注意：String.fromEnvironment 只在编译期常量表达式下生效，
    // 必须逐键显式 const 读取（循环变量运行时求值会取到默认值）。
    // 这些键只是「常用参数」快捷方式；完整参数请用 argsFile（无白名单限制）。
    const envArgs = <String, String>{
      'view': String.fromEnvironment('view'),
      'page': String.fromEnvironment('page'),
      'fid': String.fromEnvironment('fid'),
      'gid': String.fromEnvironment('gid'),
      'orderby': String.fromEnvironment('orderby'),
      'filter': String.fromEnvironment('filter'),
      'kw': String.fromEnvironment('kw'),
      'searchid': String.fromEnvironment('searchid'),
      'tid': String.fromEnvironment('tid'),
      'pid': String.fromEnvironment('pid'),
      'favid': String.fromEnvironment('favid'),
      'cid': String.fromEnvironment('cid'),
      'subject': String.fromEnvironment('subject'),
      'authorid': String.fromEnvironment('authorid'),
      'uid': String.fromEnvironment('uid'),
      'username': String.fromEnvironment('username'),
      'touid': String.fromEnvironment('touid'),
      'type': String.fromEnvironment('type'),
      'message': String.fromEnvironment('message'),
      'reppid': String.fromEnvironment('reppid'),
      'formhash': String.fromEnvironment('formhash'),
      'note': String.fromEnvironment('note'),
      'exttype': String.fromEnvironment('exttype'),
      'income': String.fromEnvironment('income'),
      'optype': String.fromEnvironment('optype'),
      'starttime': String.fromEnvironment('starttime'),
      'endtime': String.fromEnvironment('endtime'),
      'scores': String.fromEnvironment('scores'),
      'notify': String.fromEnvironment('notify'),
      'reason': String.fromEnvironment('reason'),
      // debug.http 专用：path=请求路径；q=额外 query 参数（JSON 字符串）
      'path': String.fromEnvironment('path'),
      'n': String.fromEnvironment('n'),
      'q': String.fromEnvironment('q'),
      // cache.* 专用
      'kind': String.fromEnvironment('kind'),
      'limit': String.fromEnvironment('limit'),
    };

    // 文件参数作底，显式 --dart-define 优先（空值不算显式传入）
    final args = <String, String>{
      ...fileArgs,
      for (final e in envArgs.entries)
        if (e.value.isNotEmpty) e.key: e.value,
    };

    String pick(String key, String envValue) =>
        envValue.isNotEmpty ? envValue : (fileArgs[key] ?? '');

    final rawCmd = pick('cmd', const String.fromEnvironment('cmd'));
    final cmd = rawCmd.isEmpty ? 'session.list' : rawCmd;
    final account = pick('account', const String.fromEnvironment('account'));
    final site = pick('site', const String.fromEnvironment('site'));
    final baseUrl = pick('baseUrl', const String.fromEnvironment('baseUrl'));
    final siteName = pick('siteName', const String.fromEnvironment('siteName'));
    final cookie = pick('cookie', const String.fromEnvironment('cookie'));
    final header = pick('header', const String.fromEnvironment('header'));
    final ua = pick('ua', const String.fromEnvironment('ua'));
    final rawLog = pick('log', const String.fromEnvironment('log'));
    final log = rawLog.isEmpty ? 'info' : rawLog;
    final maxList = _clampInt(
      pick('maxList', const String.fromEnvironment('maxList')),
      fallback: 3,
      min: 1,
      max: 50,
    );
    final maxStr = _clampInt(
      pick('maxStr', const String.fromEnvironment('maxStr')),
      fallback: 160,
      min: 1,
      max: 100000,
    );

    // 日志级别控制
    if (log == 'off') {
      AppLogger.enabled = false;
    } else if (log == 'debug') {
      AppLogger.level = LogLevel.debug;
    }

    final output = await runProbe(
      cmd: cmd,
      args: args,
      account: account,
      site: site,
      baseUrl: baseUrl,
      siteName: siteName,
      cookie: cookie,
      header: header,
      ua: ua,
      maxList: maxList,
      maxStr: maxStr,
    );

    print('=== API_PROBE_BEGIN ===');
    print(jsonEncode(output));
    print('=== API_PROBE_END ===');
    if (output['ok'] != true) {
      final result = output['result'];
      final reason =
          output['error'] ??
          (result is Map ? result['message'] : null) ??
          output['status'];
      throw StateError('probe failed: $reason');
    }
  });
}

Future<Map<String, dynamic>> runProbe({
  required String cmd,
  required Map<String, String> args,
  required String account,
  String site = '',
  String baseUrl = '',
  String siteName = '',
  String cookie = '',
  String header = '',
  String ua = '',
  int maxList = 3,
  int maxStr = 160,
}) async {
  // 自描述：无上下文的 AI 跑 help 即可掌握全部用法，无需读源码
  if (cmd == 'help' || cmd == '--help' || cmd == 'h') {
    return _buildHelp();
  }

  // 探针 ↔ MCP 工具覆盖矩阵（不发请求、不需要登录）
  if (cmd == 'coverage') {
    return {
      'ok': true,
      'status': 'ok',
      'cmd': 'coverage',
      'result': buildMcpCoverage(scenarios.keys),
    };
  }

  final scenario = scenarios[cmd];
  if (scenario == null) {
    return {
      'ok': false,
      'status': 'invalid_args',
      'cmd': cmd,
      'result': {
        'success': false,
        'message': '未知命令 $cmd，可用：${scenarios.keys.join(', ')}',
      },
    };
  }

  // 浏览模式白名单：显式 ua=mobile 时，PC-only 场景明确拒绝（避免误判两套等价）
  if (normalizeBrowseMode(ua) == 'mobile' && !scenario.mobileSupported) {
    return {
      'ok': false,
      'status': 'invalid_args',
      'cmd': cmd,
      'browseMode': 'mobile',
      'result': {
        'success': false,
        'message':
            '场景 $cmd 仅支持桌面模板（PC），不支持 ua=mobile：'
            '该接口的数据来自 Discuz PC 页面，移动模板下结构不同或不存在。'
            '请去掉 ua（跟随站点「浏览模式」）或改 ua=desktop 后重试。'
            '支持 ua=mobile 的场景仅：guide.list、forum.list、search.list、'
            'my.threads、user.info、debug.http。',
      },
      'usage': scenario.desc,
    };
  }

  try {
    await bootstrap(
      account: account,
      site: site,
      baseUrl: baseUrl,
      siteName: siteName,
      cookie: cookie,
      header: header,
      ua: ua,
    );
  } catch (e) {
    return {'ok': false, 'status': 'failed', 'cmd': cmd, 'error': '初始化失败: $e'};
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
          'status': 'blocked',
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
          'status': 'blocked',
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
        'ok': false,
        'status': 'invalid_args',
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
      'status': 'ok',
      'cmd': cmd,
      'params': {
        for (final k in scenario.params.keys)
          if (args[k]?.isNotEmpty ?? false) k: args[k],
      },
      'runtimeMs': sw.elapsedMilliseconds,
      'account': ApiService().activeAccount ?? '(游客)',
      // 本次运行的浏览模式：site = 跟随站点设置；mobile/desktop = ua 覆盖生效
      'browseMode': normalizeBrowseMode(ua) ?? 'site',
      'result': compactJson(
        result,
        maxList: maxList,
        maxStr: scenario.raw ? 100000 : maxStr,
      ),
      'usage': scenario.desc,
      if (maxList != 3 || maxStr != 160)
        'compact': {'maxList': maxList, 'maxStr': maxStr},
      if (probeAcwSolved > 0) 'acwSolved': probeAcwSolved,
      if (probeInterstitialHit) 'reminder': _interstitialReminder,
    };
  } catch (e) {
    // FormatException 表示业务层失败（已评分/已收藏等预期拦截），
    // 转成 result.success=false，而非管线错误。
    if (e is FormatException) {
      return {
        'ok': true,
        'status': 'business',
        'cmd': cmd,
        'result': {
          'success': false,
          'message': e.message.isNotEmpty ? e.message : '操作失败',
        },
        'runtimeMs': sw.elapsedMilliseconds,
        if (probeAcwSolved > 0) 'acwSolved': probeAcwSolved,
        if (probeInterstitialHit) 'reminder': _interstitialReminder,
      };
    }
    return {
      'ok': false,
      'status': 'failed',
      'cmd': cmd,
      'error': '$e',
      'runtimeMs': sw.elapsedMilliseconds,
      if (probeAcwSolved > 0) 'acwSolved': probeAcwSolved,
      if (probeInterstitialHit) 'reminder': _interstitialReminder,
    };
  }
}

/// 自解失败时的提示。
///
/// 正常情况下探针会自算 `acw_sc__v2` 并自动重放（见 `api_bootstrap.dart` 的
/// `_installInterstitialProbe`），不会走到这里；只有挑战结构变化或算法失效
/// （阿里云换了实现）才需要人工介入。
const String _interstitialReminder =
    '站点返回了人机验证 / 防火墙拦截页，且探针未能自动通过（挑战结构异常或算法已'
    '变更）。先用 --dart-define=log=info 看「命中人机验证，已自算 acw_sc__v2」'
    '日志；若始终失败，对照挑战页正文核对 tool/acw_challenge.dart 里的算法。';

/// 生成完整使用说明（自描述，无需读源码即可上手）
Map<String, dynamic> _buildHelp() {
  return {
    'ok': true,
    'status': 'ok',
    'cmd': 'help',
    'what': 'API 只读探针：真实请求 + 解析管线，复用 App 的 Cookie 登录态',
    'invoke': [
      r'flutter test tool/api_probe_test.dart --dart-define=cmd=<命令> --dart-define=key=value',
      r'推荐：flutter test tool/api_probe_test.dart --dart-define=argsFile=<args.json>',
      r'跨平台通用，无 shell 依赖；帮助见 docs/10-API探针使用规范.md',
    ],
    'globalParams': {
      'argsFile':
          '参数 JSON 文件路径（推荐）。文件内写 {"cmd":"thread.detail","tid":"170313",'
          '"page":"2","maxList":10}；没有参数白名单限制，也不受 & | ; 空格等字符影响。'
          '显式 --dart-define 优先级更高。',
      'maxList': '结果列表保留项数（默认 3，上限 50）。需要看全列表时调大',
      'maxStr': '字符串截断长度（默认 160，上限 100000；raw=true 场景不截断）',
      'cmd': '场景命令（默认 session.list），见下方 scenarios',
      'account': '登录账号名（空=游客）；先跑 session.list 查看可用账号',
      'site': '站点（索引或名称，空=第一个站点），如 site=1',
      'baseUrl': '任意站点 URL（测试站等不在默认列表中的站点），如 baseUrl=http://discuz.qcxs.top',
      'siteName': 'baseUrl 指定站点的显示名（空=域名）',
      'cookie':
          '临时注入的 Cookie，格式 k=v,k2=v2（也兼容 k=v; k2=v2）。'
          '写入当前账号的 CookieJar，用于防盗链 / 站点特定 Cookie；'
          '人机验证无需它（探针会自动自解）',
      'header':
          '临时注入的请求头，格式 Name:Value,Name2:Value2，加到 Dio 默认头，'
          '如 header=Referer:https://bbs.binmt.cc/',
      'ua':
          '临时换用「浏览模式」：mobile（移动模板）或 desktop/pc（桌面模板）。'
          '默认空 = 跟随站点浏览模式。**对整个运行的所有请求生效**。'
          '注意：仅少数场景支持 mobile（见各场景的 mobileSupported 标记），'
          '其余为 PC-only，传 ua=mobile 会被拒绝。',
      'log': 'off/info/debug（默认 info，off 只输出协议 JSON）',
    },
    'scenarios': {
      for (final e in scenarios.entries)
        e.key: {
          'desc': e.value.desc,
          'params': e.value.params,
          'required': [
            for (final p in e.value.params.entries)
              if (p.value.startsWith('*')) p.key,
          ],
          // 可直接复制的最小命令（cmd=xxx key=<key>）
          'minimal': _minimalCommand(e.key, e.value.params),
          'needsLogin': e.value.needsLogin,
          // 白名单：仅这些场景接受 ua=mobile；其余为 PC-only
          if (e.value.mobileSupported) 'mobileSupported': true,
        },
    },
    'examples': [
      r'flutter test tool/api_probe_test.dart --dart-define=cmd=session.list                    # 查看本机 Cookie/账号',
      r'flutter test tool/api_probe_test.dart --dart-define=cmd=guide.list --dart-define=view=newthread       # 导读（游客）',
      r'flutter test tool/api_probe_test.dart --dart-define=cmd=session.status --dart-define=account=青春向上 # 验证登录态',
      r'flutter test tool/api_probe_test.dart --dart-define=cmd=thread.detail --dart-define=tid=170313        # 帖子详情',
      r'flutter test tool/api_probe_test.dart --dart-define=cmd=debug.http --dart-define=path=/forum.php --dart-define=q=mod=guide,index=1',
      r'flutter test tool/api_probe_test.dart --dart-define=cmd=session.status --dart-define=site=1 --dart-define=account=qcxs  # 跨站点账号',
      r'flutter test tool/api_probe_test.dart --dart-define=cmd=guide.list --dart-define=log=info   # 人机验证会自解，日志可见「已自算 acw_sc__v2」',
      r'flutter test tool/api_probe_test.dart --dart-define=cmd=forum.list --dart-define=fid=2 --dart-define=ua=desktop  # 换桌面 UA 复测（默认跟随浏览模式）',
      r'flutter test tool/api_probe_test.dart --dart-define=argsFile=tool/args.example.json  # 参数文件（推荐）',
      r'flutter test tool/api_probe_test.dart --dart-define=cmd=coverage               # 探针 ↔ MCP 工具覆盖矩阵',
      r'flutter test tool/api_probe_test.dart --dart-define=cmd=cache.list             # 本机帖子缓存（不联网）',
      r'flutter test tool/api_probe_test.dart --dart-define=cmd=guide.list --dart-define=maxList=20                     # 多看几条列表',
    ],
    'tips': [
      '首次使用：先运行一次 App（flutter run -d windows）并登录，生成 Cookie；'
          '或先跑 cmd=session.list 确认本机登录状态',
      '需要登录的命令返回 blocked=true 时，追加 account=<账号名> 重试',
      '站点开启人机验证（阿里云 ESA 的 acw_sc__v2 挑战）时，探针会自动自解'
          '并重放请求，无需人工介入；输出里的 acwSolved 表示本次自解次数',
      'debug.http 的额外 query 参数用 q=k1=v1,k2=v2 逗号分隔'
          '（URL 中的 & 会被 PowerShell→cmd 拆散，禁止直接传完整 URL）',
      '用 --dart-define 时参数值不要包含 & | ; " 空格 等特殊字符；'
          '确有特殊字符或参数很多时，改用 --dart-define=argsFile=<json>',
      '大列表默认只保留前 3 项 + __more__，长字符串截断 160 字符；'
          '用 maxList / maxStr 调整，输出里的 compact 会回显实际取值',
      'cmd=coverage 会列出「有场景没工具 / 有工具没场景」的缺口，'
          '新增 MCP 工具或探针场景后跑一次可发现文档与实现脱节',
      '换 UA 复测：加 --dart-define=ua=desktop（或 mobile）临时换「浏览模式」，'
          '本次运行所有请求都按该 UA 发；某套模板解析异常时用它对照',
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
    return v.map(
      (k, val) =>
          MapEntry('$k', compactJson(val, maxList: maxList, maxStr: maxStr)),
    );
  }
  if (v is List) {
    final out = v
        .take(maxList)
        .map((e) => compactJson(e, maxList: maxList, maxStr: maxStr))
        .toList();
    if (v.length > maxList) out.add({'__more__': v.length - maxList});
    return out;
  }
  if (v is String && v.length > maxStr) {
    return '${v.substring(0, maxStr)}…(+${v.length - maxStr}字符截断)';
  }
  return v;
}

// ==================== 参数文件 / 帮助辅助 ====================

/// 读取 `--dart-define=argsFile=<path>` 指向的 JSON。
///
/// 这是绕开「compile-time 白名单」的官方方式：任意键都会原样透传给场景，
/// 值可为字符串/数字/布尔，对象与数组按 JSON 字符串传入（如 debug.http 的 q）。
Future<Map<String, String>> _loadArgsFile(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    throw ArgumentError('argsFile 不存在: $path');
  }
  final raw = jsonDecode(await file.readAsString());
  if (raw is! Map) {
    throw const FormatException('argsFile 顶层必须是 JSON 对象');
  }
  return {
    for (final e in raw.entries)
      e.key.toString(): switch (e.value) {
        String s => s,
        null => '',
        final v => jsonEncode(v),
      },
  };
}

int _clampInt(
  String raw, {
  required int fallback,
  required int min,
  required int max,
}) {
  final v = int.tryParse(raw.trim());
  if (v == null) return fallback;
  return v.clamp(min, max);
}

/// 由必填参数（文档约定以 `*` 开头）拼出可直接复制的 `cmd=... key=<key>` 命令
String _minimalCommand(String cmd, Map<String, String> params) {
  final required = [
    for (final e in params.entries)
      if (e.value.startsWith('*')) '${e.key}=<${e.key}>',
  ];
  return ['cmd=$cmd', ...required].join(' ');
}
