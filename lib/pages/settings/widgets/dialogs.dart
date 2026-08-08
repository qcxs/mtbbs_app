import 'package:flutter/material.dart';
import 'package:mtbbs/providers/settings_provider.dart';

/// 设置弹窗统一最大宽度（宽屏下不拉满全宽）
const double settingsDialogMaxWidth = 360;

/// 通用数字输入弹窗（替换旧的重复 AlertDialog + TextField 模板）。
/// [min]/[max] 仅用于提示与非法值保护，最终范围由各 setter 内部 clamp。
Future<void> showNumberDialog({
  required BuildContext context,
  required String title,
  String? description,
  required int initValue,
  int min = 0,
  int max = 100000,
  String? helperText,
  required Future<void> Function(int value) onSave,
}) async {
  final ctl = TextEditingController(text: initValue.toString());
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      constraints: const BoxConstraints(maxWidth: settingsDialogMaxWidth),
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (description != null) ...[
            Text(description),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: ctl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '数值',
              border: const OutlineInputBorder(),
              isDense: true,
              helperText:
                  helperText ??
                  (min > 0 || max < 100000 ? '$min - $max' : null),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            final v = int.tryParse(ctl.text.trim());
            if (v == null) return;
            final clamped = v.clamp(min, max);
            await onSave(clamped);
            if (ctx.mounted) Navigator.of(ctx).pop();
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
  ctl.dispose();
}

/// 单选弹窗选项
class SelectOption<T> {
  const SelectOption({
    required this.value,
    this.icon,
    required this.label,
    this.description,
  });

  final T value;
  final IconData? icon;
  final String label;
  final String? description;
}

/// 通用单选弹窗（替换旧的 UA / 头像尺寸等 ListTile 单选 AlertDialog）。
/// 返回选中的值；未选择（关闭）返回 null。
Future<T?> showSelectDialog<T>({
  required BuildContext context,
  required String title,
  required List<SelectOption<T>> options,
  required T selected,
}) {
  final cs = Theme.of(context).colorScheme;
  return showDialog<T>(
    context: context,
    builder: (ctx) => AlertDialog(
      constraints: const BoxConstraints(maxWidth: settingsDialogMaxWidth),
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final opt in options)
            ListTile(
              leading: opt.icon == null
                  ? null
                  : Icon(opt.icon, color: cs.primary),
              title: Text(opt.label),
              subtitle: opt.description == null ? null : Text(opt.description!),
              trailing: opt.value == selected
                  ? Icon(Icons.check, color: cs.primary)
                  : null,
              onTap: () => Navigator.of(ctx).pop(opt.value),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

/// 主题色选择弹窗（从原设置页抽离）
Future<void> showColorPickerDialog(
  BuildContext context,
  SettingsProvider settings,
) async {
  final mCs = Theme.of(context).colorScheme;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('主题色'),
      content: Wrap(
        spacing: 16,
        runSpacing: 16,
        alignment: WrapAlignment.center,
        children: SettingsProvider.presetColors.entries.map((e) {
          final isActive = e.value.toARGB32() == settings.seedColor.toARGB32();
          return GestureDetector(
            onTap: () {
              settings.setSeedColor(e.value);
              Navigator.of(ctx).pop();
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: e.value,
                    shape: BoxShape.circle,
                    border: isActive
                        ? Border.all(color: mCs.onSurfaceVariant, width: 3)
                        : null,
                  ),
                  child: isActive
                      ? const Icon(Icons.check, color: Colors.white, size: 22)
                      : null,
                ),
                const SizedBox(height: 4),
                Text(e.key, style: const TextStyle(fontSize: 11)),
              ],
            ),
          );
        }).toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}
