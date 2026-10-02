import 'package:flutter/material.dart';
import 'package:mtbbs/core/app/app_page_gate.dart';
import 'package:mtbbs/pages/settings/models/settings_model.dart';
import 'package:mtbbs/providers/settings_provider.dart';

/// 「页面接管」设置分组
///
/// - 全局逃生阀：整体退化为内置浏览器（无法通过人机验证时的降级方案）
/// - 逐页开关：**默认全部开启 = 走 App 自研页面**；关闭某项 = 该页改用内置浏览器
///
/// 决策逻辑与接入点见 `core/app/app_page_gate.dart`：唯一生效点是 GoRouter
/// 顶层 `redirect`，因此对所有入口（链接点击 / 卡片 / 头像 / 系统入站链接）一致。
List<SettingsModel> pageGateSettings() => [
  const HeaderSetting(
    title: '页面接管',
    subtitle: '关闭某项后，该页面无论从链接还是从列表卡片进入，都改用内置浏览器打开',
  ),
  SwitchSetting(
    title: '全部改用内置浏览器',
    subtitle:
        '逃生阀：开启后不再使用 App 页面，所有跳转都用内置浏览器打开。'
        '若被锁在浏览器里，可从浏览器右上角「设置」入口关回来',
    icon: Icons.travel_explore,
    value: (s) => s.browserOnlyMode,
    onChanged: (ctx, s, v) => s.setBrowserOnlyMode(v),
  ),
  const HeaderSetting(
    title: '逐页接管',
    subtitle: '每项控制一个页面是否仍由 App 接管（关闭 = 该页走内置浏览器）',
  ),
  for (final page in appPages)
    SwitchSetting(
      title: page.label,
      icon: page.icon,
      value: (s) => s.isAppPageEnabled(page.id),
      onChanged: (ctx, s, v) => s.setAppPageEnabled(page.id, v),
    ),
];
