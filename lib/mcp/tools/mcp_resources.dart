import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:mtbbs/mcp/mcp_sanitizer.dart';
import 'package:mtbbs/mcp/mcp_types.dart';
import 'package:mtbbs/mcp/tools/mcp_payloads.dart';

/// 注册 MCP 资源与提示词。
///
/// 与工具一致：**常驻注册**，读取/取用时才按能力开关拒绝，
/// 这样客户端缓存的 `resources/list`、`prompts/list` 不会因用户开关而失效。
void registerResources({
  required McpServer server,
  required bool Function(McpToolGroup group) isGroupEnabled,
  required McpAccountInfoProvider accountInfo,
}) {
  server.registerResource('MTBBS 应用信息', 'mtbbs://app/info', null, (
    uri,
    extra,
  ) async {
    _ensureEnabled(isGroupEnabled, McpToolGroup.appInfo);
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          text: jsonEncode(
            McpSanitizer.sanitize(McpPayloads.appInfo(accountInfo)),
          ),
          mimeType: 'application/json',
        ),
      ],
    );
  });

  server.registerResource('MTBBS 版块列表', 'mtbbs://forums', null, (
    uri,
    extra,
  ) async {
    _ensureEnabled(isGroupEnabled, McpToolGroup.publicData);
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          text: jsonEncode(McpSanitizer.sanitize(McpPayloads.forums())),
          mimeType: 'application/json',
        ),
      ],
    );
  });

  server.registerPrompt(
    'summarize_thread',
    description: '总结指定帖子：先读取楼层正文，再按要求提炼要点',
    argsSchema: {
      'tid': PromptArgumentDefinition(
        type: String,
        description: '帖子 ID（tid）',
        required: true,
      ),
      'focus': PromptArgumentDefinition(
        type: String,
        description: '关注点，例如"教程步骤""报错原因""结论"',
      ),
    },
    callback: (args, extra) async {
      _ensureEnabled(isGroupEnabled, McpToolGroup.publicData);
      final tid = (args?['tid'] ?? '').toString().trim();
      final focus = (args?['focus'] ?? '').toString().trim();
      return GetPromptResult(
        messages: [
          PromptMessage(
            role: PromptMessageRole.user,
            content: TextContent(
              text:
                  '请调用 get_thread_detail 读取帖子 tid=$tid 的正文'
                  '（必要时翻页），然后总结：\n'
                  '1. 楼主想解决的问题／分享的内容\n'
                  '2. 关键步骤或结论（保留必要代码与命令原文）\n'
                  '3. 有价值的回复与最终结论\n'
                  '${focus.isEmpty ? '' : '重点关注：$focus\n'}'
                  '只依据返回的正文作答，不要补充你从别处知道的论坛信息。',
            ),
          ),
        ],
      );
    },
  );
}

/// 能力关闭时抛错（由 SDK 转成 JSON-RPC error 返回给客户端）
void _ensureEnabled(
  bool Function(McpToolGroup) isGroupEnabled,
  McpToolGroup group,
) {
  if (isGroupEnabled(group)) return;
  throw StateError(
    '能力「${group.label}」已在 App 中关闭，'
    '请让用户在「设置 → MCP 服务 → 能力开关」中开启。',
  );
}
