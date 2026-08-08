import 'package:flutter/material.dart';

/// 单条顶栏提示数据
class EditorHintData {
  final String id;
  final IconData icon;
  final Color color;
  final String message;

  const EditorHintData({
    required this.id,
    required this.icon,
    required this.color,
    required this.message,
  });
}

/// 编辑器顶栏提示条 — 渲染多条提示，点击关闭按钮回调 [onDismiss]。
class EditorHintBar extends StatelessWidget {
  final List<EditorHintData> hints;
  final ValueChanged<String> onDismiss;

  const EditorHintBar({
    super.key,
    required this.hints,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (hints.isEmpty) return const SizedBox.shrink();
    return Container(
      color: cs.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [for (final hint in hints) _buildItem(context, cs, hint)],
      ),
    );
  }

  Widget _buildItem(BuildContext context, ColorScheme cs, EditorHintData hint) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.surfaceContainerLow)),
      ),
      child: Row(
        children: [
          Icon(hint.icon, size: 16, color: hint.color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hint.message,
              style: TextStyle(fontSize: 12, color: cs.onSurface),
            ),
          ),
          GestureDetector(
            onTap: () => onDismiss(hint.id),
            child: Container(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close, size: 14, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
