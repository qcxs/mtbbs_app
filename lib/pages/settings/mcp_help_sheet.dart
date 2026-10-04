import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mtbbs/mcp/mcp.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';

/// 打开 MCP「使用帮助」面板。
///
/// 面向第一次配置的用户：给出「开启服务 → 创建令牌 → 填入客户端」三步、
/// 可直接复制的客户端配置片段、以及常见连不上问题的排查。
Future<void> showMcpHelpSheet(
  BuildContext context,
  McpServerController controller,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // maxHeight 必须给：内容是 Column + Expanded，无上界会直接崩
    constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (_) => _McpHelpSheet(controller: controller),
  );
}

class _McpHelpSheet extends StatelessWidget {
  final McpServerController controller;
  const _McpHelpSheet({required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasToken = controller.tokens.isNotEmpty;
    // 展示用占位符；复制时若已有令牌则替换为真实值，方便直接粘贴
    final displaySnippet = _configJson(controller.endpointUrl, '<令牌>');
    final copySnippet = _configJson(
      controller.endpointUrl,
      hasToken ? controller.tokens.first.value : '<令牌>',
    );

    return Column(
      children: [
        // 拖拽手柄
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Center(
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '配置 MCP',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 当前状态提示：把"下一步该做什么"直接摆在最上面
                if (!controller.isRunning)
                  _notice(cs, '服务当前未运行——先在上一页打开「启用 MCP 服务」开关。')
                else if (!hasToken)
                  _notice(cs, '还没有访问令牌——先在上一页「访问令牌」里新建一个，否则连接会被拒绝。'),

                _section(cs, '三步接入'),
                _step(cs, 1, '开启服务', '打开「启用 MCP 服务」，确认「服务状态」显示「运行中」。'),
                _step(cs, 2, '创建令牌', '在「访问令牌」点「新建访问令牌」，填个备注（如 Trae），创建后复制令牌值。'),
                _step(
                  cs,
                  3,
                  '填入 AI 客户端',
                  '在 Trae / Claude Desktop / Cursor 等客户端的 MCP 配置里加入下面的片段，'
                      '把 <令牌> 换成第 ② 步复制的值。',
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    displaySnippet,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.copy, size: 18),
                    label: Text(hasToken ? '复制配置（含令牌）' : '复制配置'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: copySnippet));
                      showToast('配置已复制');
                    },
                  ),
                ),
                if (!hasToken) ...[
                  const SizedBox(height: 4),
                  Text(
                    '还没有令牌，复制的片段里是占位符 <令牌>，创建后请替换。',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],

                const SizedBox(height: 8),
                _section(cs, '重要说明'),
                _bullet(cs, '只读服务：只能读取论坛内容与 App 信息，不能发帖、回复、点赞、收藏。'),
                _bullet(cs, '仅本机：服务只监听 127.0.0.1，不暴露到局域网，AI 客户端需运行在同一台设备上。'),
                _bullet(cs, '能力开关：账号数据、本地记录默认关闭，需要时在上一页「能力开关」中开启。'),

                const SizedBox(height: 8),
                _section(cs, '连不上？'),
                _bullet(cs, '状态不是「运行中」：回到上一页开启开关，或点「服务状态」重试。'),
                _bullet(
                  cs,
                  '报 403 Forbidden：令牌缺失或错误——确认客户端带上了 Authorization: Bearer <令牌>。',
                ),
                _bullet(cs, '工具调用被拒绝：对应的能力分组已关闭，请在「能力开关」中开启。'),
                _bullet(cs, '改过端口：把配置里的 url 端口改成「连接信息 → 端口」显示的值。'),
                _bullet(cs, '仍不行：用上一页的「连通性测试」先在本机验证一遍端口、鉴权与工具执行。'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _notice(ColorScheme cs, String text) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: cs.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: cs.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(ColorScheme cs, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _step(ColorScheme cs, int index, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$index',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: cs.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bullet(ColorScheme cs, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('· ', style: TextStyle(color: cs.onSurfaceVariant)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// AI 客户端 MCP 配置片段（与 docs/17「客户端配置」一致）
  static String _configJson(String url, String token) {
    return '{\n'
        '  "mcpServers": {\n'
        '    "mtbbs": {\n'
        '      "url": "$url",\n'
        '      "headers": { "Authorization": "Bearer $token" }\n'
        '    }\n'
        '  }\n'
        '}';
  }
}
