import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart' show DioException;
import 'package:mcp_dart/mcp_dart.dart';
import 'package:mtbbs/config/build_config.dart';
import 'package:mtbbs/core/app/stagger_queue.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/mcp/mcp_audit.dart';
import 'package:mtbbs/mcp/mcp_sanitizer.dart';
import 'package:mtbbs/mcp/mcp_types.dart';
import 'package:mtbbs/mcp/tools/mcp_payloads.dart';
import 'package:mtbbs/mcp/tools/mcp_resources.dart';
import 'package:mtbbs/mcp/tools/mcp_tool_definition.dart';
import 'package:mtbbs/mcp/tools/mcp_tools_app.dart';
import 'package:mtbbs/mcp/tools/mcp_tools_editor.dart';
import 'package:mtbbs/mcp/tools/mcp_tools_forum.dart';
import 'package:mtbbs/mcp/tools/mcp_tools_saved.dart';
import 'package:mtbbs/mcp/tools/mcp_tools_user.dart';

/// MCP 工具注册表 —— 全部为**只读**工具，绝不提供写操作。
///
/// 职责边界：
/// - 本文件：组装 Server、统一调用包装（超时 / 审计 / 脱敏）
/// - `tools/mcp_tools_*.dart`：各分组的具体工具
/// - `tools/mcp_payloads.dart`：出站数据结构（字段白名单）
/// - `mcp_sanitizer.dart`：流式脱敏兜底
class McpToolRegistry {
  McpToolRegistry._();

  /// 单次工具调用的硬超时（防止 AI 侧挂死拖住 App）
  static const Duration callTimeout = Duration(seconds: 30);

  /// 创建 MCP Server 实例。
  ///
  /// **关闭的分组依然注册**：工具表保持稳定，客户端（Trae/Claude 等）
  /// 缓存的 `tools/list` 不会因用户开关而失效；调用时才拒绝并提示如何开启。
  /// 否则用户一改开关就得让客户端重连，体验很差。
  static McpServer createServer({
    required bool Function(McpToolGroup group) isGroupEnabled,
    required McpAccountInfoProvider accountInfo,
  }) {
    final server = McpServer(
      Implementation(name: 'mtbbs', version: BuildConfig.versionName),
      options: const McpServerOptions(
        protocol: McpProtocol.stable,
        // 连接时就把"先看 help + 只读边界"注入 AI 上下文，
        // 避免 AI 上来就乱猜工具用法。
        instructions:
            'MTBBS：Discuz 论坛的**只读**数据接口。'
            '第一次使用请先调用 help 工具，它会给出能力清单、'
            '几类典型任务（总结最近帖子 / 总结某账号 / 读编辑器草稿）的工具组合方式，'
            '以及参数约定。所有工具均只读；会发请求的工具会自动错峰排队，'
            '连续大量调用时变慢属正常保护。',
      ),
    );

    for (final def in buildTools(accountInfo)) {
      server.registerTool(
        def.name,
        description: def.description,
        inputSchema: JsonSchema.object(
          properties: def.properties,
          required: def.requiredArgs,
        ),
        annotations: const ToolAnnotations(readOnlyHint: true),
        callback: (args, extra) =>
            _invoke(def, args, enabled: isGroupEnabled(def.group)),
      );
    }

    registerResources(
      server: server,
      isGroupEnabled: isGroupEnabled,
      accountInfo: accountInfo,
    );

    return server;
  }

  /// 全部工具定义（按能力分组聚合），供注册与统计使用
  static List<McpToolDefinition> buildTools(
    McpAccountInfoProvider accountInfo,
  ) => [
    ...appTools(accountInfo),
    ...forumTools(),
    ...userTools(),
    ...savedTools(),
    ...editorTools(),
  ];

  /// 分组 → 工具数（设置页展示"已开启/全部"用，与账号信息无关）
  static Map<McpToolGroup, int> toolCountByGroup() {
    final counts = <McpToolGroup, int>{};
    for (final def in buildTools(() => const McpAccountInfo.guest())) {
      counts.update(def.group, (v) => v + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  // ==================== 调用包装（审计 + 超时 + 脱敏） ====================

  static Future<CallToolResult> _invoke(
    McpToolDefinition def,
    Map<String, dynamic> args, {
    required bool enabled,
  }) async {
    final sw = Stopwatch()..start();

    if (!enabled) {
      return _fail(
        def.name,
        sw,
        '能力「${def.group.label}」已在 App 中关闭，暂不可用。'
        '请让用户在「设置 → MCP 服务 → 能力开关」中开启后重试。',
        auditError: '能力已关闭',
      );
    }

    // 会真正发请求的工具先过全局错峰队列：AI 可能并发调用多个工具，
    // 这里逐个放行，避免短时间打出一串请求被站点风控。
    // 排队等待不计入下面的执行超时（本地工具不排队，立即执行）。
    if (def.network) await enqueueStagger().ready;

    try {
      final raw = await def.run(args).timeout(callTimeout);
      final safe = McpSanitizer.sanitize(raw);
      return _ok(def.name, safe, sw);
    } on TimeoutException {
      return _fail(
        def.name,
        sw,
        '工具 ${def.name} 超过 ${callTimeout.inSeconds} 秒未返回，已中止。'
        '可稍后重试或缩小请求范围（如减小 max_posts）。',
        auditError: '超时',
      );
    } on DioException catch (e) {
      // 论坛对不存在的帖子/用户会直接返回 4xx，Dio 默认会抛异常。
      // 这里转成 AI 能理解的说明，而不是把 DioException 原文丢出去。
      return _fail(def.name, sw, McpPayloads.describeDioError(e));
    } catch (e) {
      return _fail(def.name, sw, '工具 ${def.name} 执行失败：$e');
    }
  }

  static CallToolResult _ok(String tool, Object? data, Stopwatch sw) {
    sw.stop();
    McpAuditLog.instance.add(
      McpAuditEntry(
        time: DateTime.now(),
        tool: tool,
        ok: true,
        elapsedMs: sw.elapsedMilliseconds,
      ),
    );
    AppLogger.i('MCP', '$tool ok (${sw.elapsedMilliseconds}ms)');
    return CallToolResult(content: [TextContent(text: jsonEncode(data))]);
  }

  static CallToolResult _fail(
    String tool,
    Stopwatch sw,
    String message, {
    String? auditError,
  }) {
    sw.stop();
    McpAuditLog.instance.add(
      McpAuditEntry(
        time: DateTime.now(),
        tool: tool,
        ok: false,
        elapsedMs: sw.elapsedMilliseconds,
        error: auditError ?? message,
      ),
    );
    AppLogger.w('MCP', '$tool 失败: ${auditError ?? message}');
    return CallToolResult(isError: true, content: [TextContent(text: message)]);
  }
}
