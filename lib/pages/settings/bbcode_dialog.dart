import 'package:flutter/material.dart';
import '../../providers/settings_provider.dart';

/// BBCode 样式标签禁用对话框 — 独立组件，可在任意页面调用
class BbcodeDialog {
  static const _tagLabels = {
    'bold': '加粗 [b]',
    'italic': '斜体 [i]',
    'underline': '下划线 [u]',
    'strikethrough': '删除线 [s]',
    'color': '文字颜色 [color]',
    'size': '字号 [size]',
    'font': '字体 [font]',
    'backcolor': '背景色 [backcolor]',
    'imgDimension': '忽略图片宽高设置',
  };

  /// 可禁用的 BBCode 样式标签列表
  static const List<String> tags = [
    'bold',
    'italic',
    'underline',
    'strikethrough',
    'color',
    'size',
    'font',
    'backcolor',
    'imgDimension',
  ];

  static void show(BuildContext context, SettingsProvider settings) {
    // 本地快照，关闭时统一提交
    var localDisabled = Set<String>.from(settings.disabledBbcodeTags);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Row(
            children: [
              const Expanded(child: Text('禁用样式标签')),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () {
                  settings.setDisabledBbcodeTags(localDisabled);
                  Navigator.of(ctx).pop();
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          constraints: const BoxConstraints(maxWidth: 400),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: tags.map((tag) {
              final label = _tagLabels[tag] ?? tag;
              final enabled = !localDisabled.contains(tag);
              return CheckboxListTile(
                value: enabled,
                title: Text(label, style: const TextStyle(fontSize: 14)),
                dense: true,
                controlAffinity: ListTileControlAffinity.trailing,
                onChanged: (v) {
                  setD(() {
                    if (v == true) {
                      localDisabled.remove(tag);
                    } else {
                      localDisabled.add(tag);
                    }
                  });
                },
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () {
                settings.setDisabledBbcodeTags(localDisabled);
                Navigator.of(ctx).pop();
              },
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }
}
