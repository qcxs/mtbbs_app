/// 调试场景：原始 HTTP 获取，用于 parse 开发时对照真实 DOM
library;

import 'package:dio/dio.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/services/api_service.dart';
import 'scenario_types.dart';

/// 调试场景注册表（命令名 → 场景）
final Map<String, ApiScenario> debugScenarios = {
  'debug.http': ApiScenario(
    desc:
        '调试用：GET 指定路径，输出状态码/重定向链/响应头（set-cookie、location）'
        '/原始正文（携带当前会话 Cookie，用于 parse 开发时对照 DOM 结构）',
    params: {
      'path': '请求路径（默认 /forum.php，也可传完整 URL）',
      'q': '额外 query 参数，k=v 逗号分隔，如 mod=guide,index=1',
      'n': '正文最多输出字符数（默认 1200）',
    },
    raw: true,
    run: (a) async {
      final dio = ApiService().dio;
      final n = int.tryParse(a['n'] ?? '') ?? 1200;
      // path/n/q 以外的固定键 + q 里的 k=v 共同组成 query 参数。
      // 不用 JSON 是因为引号会被 PowerShell→cmd 传递剥离；
      // 逗号在 PowerShell/cmd 中均无特殊含义，传参零风险。
      final query = <String, String>{
        for (final e in a.entries)
          if (e.key != 'path' &&
              e.key != 'n' &&
              e.key != 'q' &&
              e.value.isNotEmpty)
            e.key: e.value,
      };
      for (final pair in (a['q'] ?? '').split(',')) {
        final idx = pair.indexOf('=');
        if (idx > 0) {
          final k = pair.substring(0, idx).trim();
          final v = pair.substring(idx + 1).trim();
          if (k.isNotEmpty) query[k] = v;
        }
      }
      final uri = Uri.parse(SiteStore.instance.baseUrl)
          .resolve(a['path'] ?? '/forum.php')
          .replace(queryParameters: query.isEmpty ? null : query);
      final resp = await dio.get<String>(uri.toString());
      final body = resp.data ?? '';
      final show = body.length > n
          ? '${body.substring(0, n)}…(+${body.length - n}字符截断)'
          : body;
      return {
        'url': uri.toString(),
        'statusCode': resp.statusCode,
        // 重定向链：站点"回退上一级"是 302 还是 JS 跳，在这里一眼可见
        'redirects': [
          for (final r in resp.redirects) '${r.statusCode} → ${r.location}',
        ],
        'contentType': resp.headers.value(Headers.contentTypeHeader),
        // 站点"记忆"了什么配置，全在 Set-Cookie 里（其余头无助于排查）
        'responseHeaders': {
          for (final e in resp.headers.map.entries)
            if (const {
              'set-cookie',
              'location',
              'server',
            }.contains(e.key.toLowerCase()))
              e.key: e.value,
        },
        'bodyLength': body.length,
        'body': show,
      };
    },
  ),
};
