import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/pages/settings/models/settings_model.dart';
import 'package:mtbbs/pages/settings/shortcut_sheet.dart';

/// 编辑与快捷键组设置项
List<SettingsModel> editorSettings() => [
  NormalSetting(
    title: '编辑器设置',
    subtitle: '快照、工具栏排序等',
    icon: Icons.settings,
    onTap: (ctx, s) => ctx.push('/settings/editor'),
  ),
  SwitchSetting(
    title: '编辑器启动自检',
    subtitle: '关闭后编辑器忽略启动报错（如未登录、无权限等），无条件进入',
    icon: Icons.auto_fix_high,
    value: (s) => s.editorStartupCheck,
    onChanged: (ctx, s, v) => s.setEditorStartupCheck(v),
  ),
  NormalSetting(
    title: '插入格式',
    subtitle: '引用帖子/用户时格式化文本',
    icon: Icons.format_quote,
    onTap: (ctx, s) => ctx.push('/settings/history-format'),
  ),
  NormalSetting(
    title: '快捷键',
    subtitle: '全局快捷键与编辑器工具栏快捷键',
    icon: Icons.keyboard,
    onTap: (ctx, s) => showShortcutSheet(ctx),
  ),
];
