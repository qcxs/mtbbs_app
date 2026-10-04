import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mtbbs/mcp/mcp.dart';
import 'package:mtbbs/mcp/tools/mcp_tool_definition.dart';
import 'package:mtbbs/mcp/tools/mcp_tool_registry.dart';
import 'package:mtbbs/pages/settings/mcp_help_sheet.dart';
import 'package:mtbbs/pages/settings/mcp_token_dialogs.dart';
import 'package:mtbbs/pages/settings/models/settings_model.dart';
import 'package:mtbbs/pages/settings/widgets/dialogs.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';

/// MCP 服务组设置项（一级设置分组）
///
/// 全部为声明式描述，实时值直接读 [McpServerController]（唯一状态源）：
/// 动态内容一律走 `subtitleBuilder` / `trailingBuilder` / 闭包，
/// 不用静态字符串 —— 分组模型由分组页每次构建时重新生成。
List<SettingsModel> mcpSettings() {
  final c = McpServerController.instance;
  // 各能力分组的工具（名/描述），供「能力开关」展开时展示
  final tools = McpToolRegistry.buildTools(() => const McpAccountInfo.guest());
  final toolsByGroup = <McpToolGroup, List<McpToolDefinition>>{};
  for (final tool in tools) {
    toolsByGroup.putIfAbsent(tool.group, () => []).add(tool);
  }
  return [
    // 帮助放最前：第一次来的用户先知道"怎么配置"，再往下逐项操作
    NormalSetting(
      title: '使用帮助',
      icon: Icons.help_outline,
      subtitle: '三步接入 Trae / Claude / Cursor，含可复制的配置片段',
      onTap: (ctx, s) => showMcpHelpSheet(ctx, c),
    ),
    HeaderSetting(title: '服务', subtitle: '只读；仅监听本机 127.0.0.1，并要求访问令牌'),
    SwitchSetting(
      title: '启用 MCP 服务',
      subtitle: '让 AI 客户端读取论坛内容与 App 信息',
      icon: Icons.hub,
      value: (s) => c.enabled,
      onChanged: (ctx, s, v) => c.setEnabled(v),
    ),
    NormalSetting(
      title: '服务状态',
      icon: Icons.sensors,
      subtitleBuilder: (s) => _statusLabel(c),
      trailingBuilder: (ctx, s) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${c.enabledToolCount}/${c.totalToolCount} 个工具',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
            ),
          ),
          if (c.status == McpServerStatus.error)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                Icons.refresh,
                size: 18,
                color: Theme.of(ctx).colorScheme.outline,
              ),
            ),
        ],
      ),
      onTap: (ctx, s) {
        if (c.status == McpServerStatus.error) c.start();
      },
    ),

    HeaderSetting(title: '连接信息'),
    NormalSetting(
      title: '端口',
      icon: Icons.settings_ethernet,
      subtitleBuilder: (s) => '${c.port}',
      onTap: (ctx, s) => showNumberDialog(
        context: ctx,
        title: 'MCP 端口',
        description: 'AI 客户端通过该端口连接本机 MCP 服务。修改后服务会自动重启。',
        initValue: c.port,
        min: McpServerController.minPort,
        max: McpServerController.maxPort,
        helperText: '默认 ${McpServerController.defaultPort}',
        onSave: c.setPort,
      ),
    ),
    NormalSetting(
      title: 'MCP 端点',
      icon: Icons.link,
      subtitleBuilder: (s) => c.endpointUrl,
      trailing: IconButton(
        tooltip: '复制',
        icon: const Icon(Icons.copy),
        onPressed: () => _copy(c.endpointUrl, '端点地址已复制'),
      ),
      onTap: (ctx, s) => _copy(c.endpointUrl, '端点地址已复制'),
    ),

    HeaderSetting(
      title: '访问令牌',
      subtitle: '像 API Key 一样手动管理：可创建多个、加备注、随时刷新或删除',
    ),
    if (c.tokens.isEmpty)
      const InfoSetting(
        title: '尚未创建令牌',
        subtitle: '没有令牌时所有连接都会被拒绝',
        icon: Icons.warning_amber,
      ),
    for (final token in c.tokens)
      NormalSetting(
        title: token.note,
        icon: Icons.vpn_key,
        subtitleBuilder: (s) =>
            '${token.masked} · 创建于 ${_formatTime(token.createdAt)}',
        trailing: IconButton(
          tooltip: '复制',
          icon: const Icon(Icons.copy),
          onPressed: () => _copy(token.value, '令牌已复制'),
        ),
        onTap: (ctx, s) => showMcpTokenDetailSheet(ctx, c, token),
      ),
    NormalSetting(
      title: '新建访问令牌',
      icon: Icons.add,
      subtitleBuilder: (s) => '可创建多个，分别给不同客户端使用',
      trailing: const SizedBox.shrink(),
      onTap: (ctx, s) => showCreateMcpTokenDialog(ctx, c),
    ),

    HeaderSetting(
      title: '能力开关',
      subtitle: '关闭后 AI 仍能看到工具，但调用会被拒绝（工具列表保持稳定，无需重连）',
    ),
    for (final group in McpToolGroup.values)
      ExpandableSwitchSetting(
        title: group.label,
        subtitle:
            '${group.description}（${toolsByGroup[group]?.length ?? 0} 个工具）',
        icon: _groupIcon(group),
        value: (s) => c.isGroupEnabled(group),
        onChanged: (ctx, s, v) => c.setGroupEnabled(group, v),
        // 点按行展开：列出该组的具体工具，让开关"看得见管什么"
        detailBuilder: (ctx, s) => _groupTools(
          ctx,
          toolsByGroup[group] ?? const <McpToolDefinition>[],
          c.isGroupEnabled(group),
        ),
      ),

    HeaderSetting(
      title: '连通性测试',
      subtitle: '在本机走一遍完整 MCP 协议（列工具 + 调用一次），验证端口、鉴权与工具执行',
    ),
    NormalSetting(
      title: '开始测试',
      icon: Icons.network_check,
      subtitleBuilder: (s) => _testLabel(c),
      trailingBuilder: (ctx, s) => c.testing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              Icons.play_arrow,
              color: c.isRunning ? null : Theme.of(ctx).colorScheme.outline,
            ),
      onTap: (ctx, s) {
        if (c.isRunning) c.selfTest();
      },
    ),

    HeaderSetting(title: '调用记录', subtitle: '仅保存在内存中，重启后清空'),
    InfoSetting(
      title: '最近调用',
      icon: Icons.receipt_long,
      subtitleBuilder: (s) => _auditText(),
    ),
    NormalSetting(
      title: '清空调用记录',
      icon: Icons.delete_outline,
      subtitleBuilder: (s) => '共 ${McpAuditLog.instance.entries.length} 条',
      trailing: const SizedBox.shrink(),
      onTap: (ctx, s) => McpAuditLog.instance.clear(),
    ),
  ];
}

// ==================== 局部逻辑 ====================

IconData _groupIcon(McpToolGroup group) => switch (group) {
  McpToolGroup.appInfo => Icons.info_outline,
  McpToolGroup.publicData => Icons.forum,
  McpToolGroup.editorRead => Icons.edit_note,
  McpToolGroup.accountData => Icons.bookmark_border,
  McpToolGroup.localData => Icons.history,
};

/// 「能力开关」展开后显示的工具清单（名称 + 描述）
Widget _groupTools(
  BuildContext context,
  List<McpToolDefinition> tools,
  bool enabled,
) {
  final cs = Theme.of(context).colorScheme;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < tools.length; i++) ...[
        if (i > 0) const SizedBox(height: 10),
        Text(
          tools[i].name,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: enabled ? cs.onSurface : cs.onSurfaceVariant,
          ),
        ),
        Text(
          tools[i].description,
          style: TextStyle(
            fontSize: 11,
            height: 1.4,
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    ],
  );
}

String _statusLabel(McpServerController c) => switch (c.status) {
  McpServerStatus.running => '运行中 · ${c.endpointUrl}',
  McpServerStatus.starting => '启动中…',
  McpServerStatus.error => '启动失败：${c.lastError ?? '未知错误'}（点击重试）',
  McpServerStatus.stopped => '已停止：开启后 AI 客户端才能连接',
};

String _testLabel(McpServerController c) {
  if (c.testing) return '测试中…';
  if (!c.isRunning) return '服务未运行，先开启 MCP 服务';
  if (!c.hasToken) return '尚未创建访问令牌，先在上方新建一个';
  final result = c.lastSelfTest;
  if (result == null) return '点按后在本机发起一次真实 MCP 请求';
  return result.ok
      ? '${result.message}（${result.elapsedMs}ms）'
      : result.message;
}

String _auditText() {
  final entries = McpAuditLog.instance.entries;
  if (entries.isEmpty) return '暂无调用';
  return entries
      .take(8)
      .map(
        (e) =>
            '${_hhmmss(e.time)}  ${e.tool}  '
            '${e.ok ? '成功 ${e.elapsedMs}ms' : '失败：${e.error ?? '未知错误'}'}',
      )
      .join('\n');
}

String _hhmmss(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}:'
    '${t.second.toString().padLeft(2, '0')}';

String _formatTime(DateTime t) =>
    '${t.year}/${t.month}/${t.day} '
    '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}';

Future<void> _copy(String text, String toast) async {
  await Clipboard.setData(ClipboardData(text: text));
  showToast(toast);
}
