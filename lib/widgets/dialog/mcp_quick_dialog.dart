import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/mcp/mcp.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart'; // rootNavigatorKey（全局根 Overlay）

/// MCP 快捷开关弹窗 —— **任意页面可用**。
///
/// 两个入口共用这一份实现：
/// 1. Windows 自绘标题栏的「MCP 已开启」徽章（点击）
/// 2. Android 常驻通知（点通知 → 平台通道 → 这里）
///
/// （「我的」页顶部还有一个 MCP 快捷开关按钮，但它是**一键直接开/关**、
/// 不弹窗，见 `my_profile_page.dart`。）
///
/// 前两处都不属于某个具体页面——通知点击甚至可能发生在**冷启动首帧之前**，
/// 那时任何页面的 context 都不存在。因此统一通过 [rootNavigatorKey] 取根
/// Overlay，不依赖调用方 context（与 `showToast` 同一套全局 Overlay 思路）。
///
/// 根未就绪时先等一帧再取一次；仍取不到就静默放弃（启动极早期，无 UI 可依附）。
///
/// 弹窗内只保留**一个**开关控件（开关行），不另设同语义的主按钮（见 actions 注释）；
/// 右上角提供直达 `/settings/mcp` 的入口（与设置页「MCP 服务」分组同一份声明）。
Future<void> showMcpQuickDialog() async {
  var context = rootNavigatorKey.currentContext;
  if (context == null) {
    await WidgetsBinding.instance.endOfFrame;
    context = rootNavigatorKey.currentContext;
  }
  if (context == null) return;
  await showDialog<void>(
    context: context,
    builder: (_) => const _McpQuickDialog(),
  );
}

/// 弹窗内容：状态一瞥 + 一键开/关
class _McpQuickDialog extends StatelessWidget {
  const _McpQuickDialog();

  @override
  Widget build(BuildContext context) {
    final controller = McpServerController.instance;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        return AlertDialog(
          constraints: const BoxConstraints(maxWidth: 400),
          title: Row(
            children: [
              Icon(Icons.hub_outlined, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('MCP 服务', style: TextStyle(fontSize: 16)),
              ),
              // 右上角：直达 MCP 设置（端口 / 令牌 / 能力开关 / 连通性测试）
              IconButton(
                icon: const Icon(Icons.settings_outlined, size: 20),
                tooltip: 'MCP 设置',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  // 先取出 router 再 pop：pop 之后本 context 即将失效
                  final router = GoRouter.of(context);
                  Navigator.of(context).pop();
                  router.push('/settings/mcp');
                },
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: '关闭',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _statusRow(cs, controller),
              const SizedBox(height: 12),
              Divider(height: 1, color: cs.outlineVariant),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '启用 MCP 服务',
                      style: TextStyle(fontSize: 14, color: cs.onSurface),
                    ),
                  ),
                  Switch(
                    value: controller.enabled,
                    onChanged: (v) => controller.setEnabled(v),
                  ),
                ],
              ),
              Text(
                '仅监听本机 127.0.0.1，并要求访问令牌',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          // 只有「关闭窗口」：开/关由上面的开关承载，不再另设一个同一语义的
          // 主按钮（两处都能开关 = 用户看到两套入口）
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭窗口'),
            ),
          ],
        );
      },
    );
  }

  /// 状态行：状态点 + 文案（运行中附带端点，便于直接复制给 AI 客户端）
  Widget _statusRow(ColorScheme cs, McpServerController c) {
    final (color, label) = switch (c.status) {
      McpServerStatus.running => (cs.primary, '运行中'),
      McpServerStatus.starting => (cs.tertiary, '启动中…'),
      McpServerStatus.error => (cs.error, '启动失败'),
      McpServerStatus.stopped => (cs.outline, '已停止'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            if (c.isRunning) ...[
              const SizedBox(width: 8),
              Text(
                '${c.enabledToolCount}/${c.totalToolCount} 个工具',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(switch (c.status) {
          McpServerStatus.error => c.lastError ?? '未知错误',
          McpServerStatus.running => c.endpointUrl,
          McpServerStatus.starting => '正在绑定 127.0.0.1:${c.port}…',
          McpServerStatus.stopped => '开启后 AI 客户端才能连接',
        }, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        if (!c.hasToken)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '尚无访问令牌，连接会被拒绝（点右上角进设置新建）',
              style: TextStyle(fontSize: 12, color: cs.error),
            ),
          ),
      ],
    );
  }
}
