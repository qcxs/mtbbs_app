import 'package:flutter/material.dart';
import 'package:mtbbs/pages/settings/bbcode_dialog.dart';
import 'package:mtbbs/pages/settings/models/settings_model.dart';
import 'package:mtbbs/pages/settings/widgets/dialogs.dart';

/// 阅读与渲染组设置项
List<SettingsModel> contentSettings() => [
  NormalSetting(
    title: '正文字号',
    icon: Icons.format_size,
    subtitleBuilder: (s) => '${s.fontSize.round()}px，默认 16px',
    onTap: (ctx, s) => showNumberDialog(
      context: ctx,
      title: '正文字号',
      description:
          '帖子正文的基准字号（12-32px），引用与代码块同步；'
          '与系统字体大小叠加生效。',
      initValue: s.fontSize.round(),
      min: 12,
      max: 32,
      helperText: '默认 16px',
      onSave: (v) => s.setFontSize(v.toDouble()),
    ),
  ),
  NormalSetting(
    title: '禁用样式标签',
    icon: Icons.palette_outlined,
    subtitleBuilder: (s) => s.disabledBbcodeTags.isEmpty
        ? '全部已启用'
        : '已禁用 ${s.disabledBbcodeTags.length} 种',
    onTap: (ctx, s) => BbcodeDialog.show(ctx, s),
  ),
  SwitchSetting(
    title: '自动识别链接',
    subtitle: '纯文本 http(s) URL 自动转为可点击链接',
    icon: Icons.link,
    value: (s) => s.autoDetectUrls,
    onChanged: (ctx, s, v) => s.setAutoDetectUrls(v),
  ),
];
