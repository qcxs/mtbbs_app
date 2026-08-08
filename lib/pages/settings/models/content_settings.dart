import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/pages/settings/bbcode_dialog.dart';
import 'package:mtbbs/pages/settings/models/settings_model.dart';

/// 内容渲染组设置项
List<SettingsModel> contentSettings() => [
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
  NormalSetting(
    title: '插入格式',
    subtitle: '编辑器引用时格式化文本',
    icon: Icons.format_quote,
    onTap: (ctx, s) => ctx.push('/settings/history-format'),
  ),
];
