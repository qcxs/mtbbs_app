import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mtbbs/mcp/mcp.dart';
import 'package:mtbbs/pages/settings/widgets/dialogs.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';
import 'package:mtbbs/widgets/dialog/confirm_dialog.dart';

/// 新建访问令牌：先填备注 → 生成 → 打开详情展示完整值
Future<void> showCreateMcpTokenDialog(
  BuildContext context,
  McpServerController controller,
) async {
  final note = await showMcpTokenNoteDialog(
    context,
    title: '新建访问令牌',
    description: '备注用于区分使用它的客户端，例如「Trae」「Claude Desktop」。',
    initial: '',
    confirmText: '创建',
  );
  if (note == null) return;
  final token = await controller.createToken(note: note);
  if (!context.mounted) return;
  await showMcpTokenDetailSheet(context, controller, token);
}

/// 令牌详情面板：查看完整值 + 改名 / 刷新 / 删除
Future<void> showMcpTokenDetailSheet(
  BuildContext context,
  McpServerController controller,
  McpToken token,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560, maxHeight: 600),
    builder: (_) => _TokenDetailSheet(
      controller: controller,
      tokenId: token.id,
    ),
  );
}

/// 备注输入弹窗（返回 null 表示取消；允许空串 = 未命名）
Future<String?> showMcpTokenNoteDialog(
  BuildContext context, {
  required String title,
  String? description,
  required String initial,
  String confirmText = '确定',
}) => showDialog<String>(
  context: context,
  builder: (_) => _TokenNoteDialog(
    title: title,
    description: description,
    initial: initial,
    confirmText: confirmText,
  ),
);

// ==================== 内部实现 ====================

/// 备注弹窗 —— 自持 controller 并在 dispose 释放
class _TokenNoteDialog extends StatefulWidget {
  const _TokenNoteDialog({
    required this.title,
    required this.description,
    required this.initial,
    required this.confirmText,
  });

  final String title;
  final String? description;
  final String initial;
  final String confirmText;

  @override
  State<_TokenNoteDialog> createState() => _TokenNoteDialogState();
}

class _TokenNoteDialogState extends State<_TokenNoteDialog> {
  late final TextEditingController _ctl = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      constraints: const BoxConstraints(maxWidth: settingsDialogMaxWidth),
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.description != null) ...[
            Text(widget.description!, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _ctl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: '备注',
              hintText: '例如：Trae',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_ctl.text.trim()),
          child: Text(widget.confirmText),
        ),
      ],
    );
  }
}

/// 详情面板内容 —— 订阅 controller，刷新令牌值后立即反映
class _TokenDetailSheet extends StatelessWidget {
  const _TokenDetailSheet({required this.controller, required this.tokenId});

  final McpServerController controller;
  final String tokenId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final index = controller.tokens.indexWhere((t) => t.id == tokenId);
        if (index < 0) {
          // 已被删除（例如在别处删掉）：面板内容退化为提示
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text('该令牌已被删除'),
          );
        }
        final token = controller.tokens[index];
        final cs = Theme.of(context).colorScheme;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  token.note,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '创建于 ${_formatTime(token.createdAt)}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    token.value,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '把上面这串填到 AI 客户端的 Authorization 头，格式为 Bearer <令牌>。',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                const Divider(height: 24),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.copy),
                  title: const Text('复制令牌'),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: token.value));
                    showToast('令牌已复制');
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.drive_file_rename_outline),
                  title: const Text('修改备注'),
                  onTap: () => _rename(context),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.autorenew),
                  title: const Text('刷新令牌值'),
                  subtitle: const Text('保留备注，重新生成一串新令牌'),
                  onTap: () => _refresh(context),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline, color: cs.error),
                  title: Text('删除令牌', style: TextStyle(color: cs.error)),
                  onTap: () => _delete(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _rename(BuildContext context) async {
    final token = controller.tokens.firstWhere((t) => t.id == tokenId);
    final note = await showMcpTokenNoteDialog(
      context,
      title: '修改备注',
      initial: token.note,
      confirmText: '保存',
    );
    if (note == null) return;
    await controller.renameToken(tokenId, note);
  }

  Future<void> _refresh(BuildContext context) async {
    final ok = await showConfirmDialog(
      context,
      title: '刷新令牌值？',
      message: '刷新后旧令牌立即失效，使用它的 AI 客户端需要更新配置。备注保持不变。',
      confirmText: '刷新',
      danger: true,
    );
    if (ok != true) return;
    await controller.refreshToken(tokenId);
    showToast('令牌已刷新，请更新客户端配置');
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除该令牌？',
      message: '删除后使用它的 AI 客户端会立即连不上。',
      confirmText: '删除',
      danger: true,
    );
    if (ok != true) return;
    await controller.deleteToken(tokenId);
    if (context.mounted) Navigator.of(context).pop();
    showToast('令牌已删除');
  }
}

String _formatTime(DateTime t) =>
    '${t.year}/${t.month}/${t.day} '
    '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}';
