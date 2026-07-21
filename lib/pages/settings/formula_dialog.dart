import 'package:flutter/material.dart';
import '../../providers/settings_provider.dart';

/// 积分公式查看对话框 — 独立组件，可在任意页面调用
class FormulaDialog {
  static void show(BuildContext context, SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final cs = Theme.of(ctx).colorScheme;
          return AlertDialog(
            title: Row(
              children: [
                const Expanded(child: Text('积分公式')),
                GestureDetector(
                  onTap: () async {
                    final result = await settings.fetchAndUpdateFormula();
                    if (ctx.mounted) {
                      setD(() {});
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: Text(
                            result != null ? '公式已更新' : '刷新失败（可能未登录）',
                          ),
                        ),
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.refresh,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            constraints: const BoxConstraints(maxWidth: 400),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '当前公式：',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      settings.creditFormula,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SizedBox.shrink(),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }
}
