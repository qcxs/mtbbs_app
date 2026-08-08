import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/pages/settings/models/settings_model.dart';

/// 编辑器组设置项
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
];
