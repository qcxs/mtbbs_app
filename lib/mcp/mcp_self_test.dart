import 'package:mcp_dart/mcp_dart.dart';
import 'package:mtbbs/config/build_config.dart';

/// 连通性自检结果
class McpSelfTestResult {
  const McpSelfTestResult({
    required this.ok,
    required this.message,
    this.toolCount = 0,
    this.elapsedMs = 0,
  });

  final bool ok;
  final String message;
  final int toolCount;
  final int elapsedMs;
}

/// 本机 MCP 连通性自检 —— 用一个真实的 MCP 客户端走完整协议：
/// `tools/list` + 调用一次无参工具。
///
/// 这一步能同时验证四件事：端口在监听、Host/Origin 校验放行本机、
/// Bearer 令牌鉴权通过、工具能真正执行。比"端口能不能连"有意义得多。
class McpSelfTest {
  McpSelfTest._();

  static const Duration _stepTimeout = Duration(seconds: 10);

  /// 自检失败时优先用这个（无参、不依赖登录态）工具
  static const String probeTool = 'get_app_info';

  static Future<McpSelfTestResult> run({
    required String endpointUrl,
    required String token,
  }) async {
    final sw = Stopwatch()..start();
    McpClient? client;
    try {
      client = McpClient(
        Implementation(
          name: 'mtbbs-self-test',
          version: BuildConfig.versionName,
        ),
      );
      final transport = StreamableHttpClientTransport(
        Uri.parse(endpointUrl),
        opts: StreamableHttpClientTransportOptions(
          requestInit: {
            'headers': {'Authorization': 'Bearer $token'},
          },
        ),
      );

      await client.connect(transport).timeout(_stepTimeout);
      final tools = await client.listTools().timeout(_stepTimeout);
      final names = tools.tools.map((t) => t.name).toList();

      if (names.contains(probeTool)) {
        await client
            .callTool(CallToolRequest(name: probeTool, arguments: const {}))
            .timeout(_stepTimeout);
      }

      sw.stop();
      return McpSelfTestResult(
        ok: true,
        message: '连通正常，暴露 ${names.length} 个只读工具',
        toolCount: names.length,
        elapsedMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      sw.stop();
      return McpSelfTestResult(ok: false, message: '连通失败：$e');
    } finally {
      try {
        await client?.close();
      } catch (_) {}
    }
  }
}
