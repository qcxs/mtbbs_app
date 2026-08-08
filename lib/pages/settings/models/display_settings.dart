import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mtbbs/config/nav_config.dart';
import 'package:mtbbs/core/app/avatar_url.dart';
import 'package:mtbbs/pages/settings/default_tab_dialog.dart';
import 'package:mtbbs/pages/settings/models/settings_model.dart';
import 'package:mtbbs/pages/settings/widgets/dialogs.dart';
import 'package:mtbbs/providers/settings_provider.dart';

/// 界面组设置项
List<SettingsModel> displaySettings() => [
  if (Platform.isWindows)
    SwitchSetting(
      title: '显示窗口标题栏',
      subtitle: '关闭后隐藏原生标题栏（需重启应用生效）',
      icon: Icons.window,
      value: (s) => s.showWindowTitleBar,
      onChanged: (ctx, s, v) => s.setShowWindowTitleBar(v),
    ),
  NormalSetting(
    title: '默认启动页',
    icon: Icons.tab,
    subtitleBuilder: (s) => _tabNameFor(s.defaultTabIndex),
    onTap: (ctx, s) => DefaultTabDialog.show(ctx, s),
  ),
  NormalSetting(
    title: '主题色',
    icon: Icons.palette,
    subtitleBuilder: (s) => _colorNameFor(s.seedColor),
    onTap: (ctx, s) => showColorPickerDialog(ctx, s),
  ),
  SwitchSetting(
    title: '纯黑主题',
    subtitle: '深色模式下使用纯黑背景',
    icon: Icons.dark_mode,
    value: (s) => s.isPureBlackTheme,
    onChanged: (ctx, s, v) => s.setPureBlackTheme(v),
  ),
  NormalSetting(
    title: '图片最大宽度',
    icon: Icons.photo_size_select_large,
    subtitleBuilder: (s) => '${s.maxImageWidth}px，窄屏自动占满',
    onTap: (ctx, s) => showNumberDialog(
      context: ctx,
      title: '图片最大宽度',
      description: '宽屏下帖子图片的最大宽度（100-2000px）。窄屏（手机）不受限制，自动占满宽度。',
      initValue: s.maxImageWidth,
      min: 100,
      max: 2000,
      helperText: '默认 600px',
      onSave: (v) => s.setMaxImageWidth(v),
    ),
  ),
  SwitchSetting(
    title: '显示头像',
    subtitle: '关闭后不再请求头像图片，仅显示文字',
    icon: Icons.face,
    value: (s) => s.showAvatars,
    onChanged: (ctx, s, v) => s.setShowAvatars(v),
  ),
  NormalSetting(
    title: '头像尺寸',
    icon: Icons.photo_size_select_actual,
    subtitleBuilder: (s) => s.avatarSizeMode.label,
    onTap: (ctx, s) => _showAvatarSizeDialog(ctx, s),
  ),
];

Future<void> _showAvatarSizeDialog(
  BuildContext context,
  SettingsProvider settings,
) async {
  final picked = await showSelectDialog<AvatarSizeMode>(
    context: context,
    title: '头像尺寸',
    options: [
      for (final mode in AvatarSizeMode.values)
        SelectOption(
          value: mode,
          icon: _avatarSizeIcon(mode),
          label: mode.label,
          description: _avatarSizeDesc(mode),
        ),
    ],
    selected: settings.avatarSizeMode,
  );
  if (picked != null) await settings.setAvatarSizeMode(picked);
}

String _tabNameFor(int index) {
  if (index < 0 || index >= navItems.length) return '';
  return navItems[index].label;
}

String _colorNameFor(Color color) {
  for (final entry in SettingsProvider.presetColors.entries) {
    if (entry.value.toARGB32() == color.toARGB32()) return entry.key;
  }
  return '自定义';
}

IconData _avatarSizeIcon(AvatarSizeMode mode) {
  switch (mode) {
    case AvatarSizeMode.auto:
      return Icons.auto_awesome;
    case AvatarSizeMode.small:
      return Icons.photo_size_select_small;
    case AvatarSizeMode.middle:
      return Icons.photo_size_select_actual;
    case AvatarSizeMode.big:
      return Icons.photo_size_select_large;
  }
}

String _avatarSizeDesc(AvatarSizeMode mode) {
  switch (mode) {
    case AvatarSizeMode.auto:
      return '按头像显示大小自动选择 small / middle / big（原行为）';
    case AvatarSizeMode.small:
      return '所有头像统一加载小尺寸';
    case AvatarSizeMode.middle:
      return '所有头像统一加载中尺寸（默认）';
    case AvatarSizeMode.big:
      return '所有头像统一加载大尺寸';
  }
}
