import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/pages/settings/models/settings_model.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';

/// 开发者选项 — 独立页，**不在设置主页出现**
///
/// 入口：关于页的应用图标**连续点击 7 次**解锁（仅首次），此后图标单击即进入本页；
/// 页底可关闭，关闭后入口消失、值保留。
///
/// 收纳标准：默认值就是对的、改错会导致"用不了"或难以自查的排障 / 诊断类开关。
/// 新增项直接往这个列表里加即可，页面会自动渲染（复用 `SettingsGroupPage`）。
List<SettingsModel> developerSettings() => [
  const HeaderSetting(title: '人机验证', subtitle: '正常情况下无需改动；仅在排查验证页本身的问题时才需要'),
  SwitchSetting(
    title: '改用网页完成',
    subtitle: '跳过本地自动通过，强制弹出内置浏览器手动完成',
    icon: Icons.open_in_browser,
    value: (s) => s.acwForceWebview,
    onChanged: (ctx, s, v) => s.setAcwForceWebview(v),
  ),
  const HeaderSetting(title: '入口', subtitle: '关闭后本页入口消失（上面的开关值会保留）'),
  NormalSetting(
    title: '关闭开发者选项',
    icon: Icons.lock_outline,
    subtitle: '需要再次进入时，回到关于页连点图标 7 次',
    onTap: (ctx, s) async {
      await s.setDeveloperMode(false);
      if (ctx.mounted) ctx.pop();
      showToast('已关闭开发者选项');
    },
  ),
];
