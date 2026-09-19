import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/config/build_config.dart';
import 'package:mtbbs/pages/settings/models/settings_model.dart';

/// 关于入口 — 单独一行，不参与分组（「通用错峰间隔」已归入站点与网络组）
List<SettingsModel> aboutSettings() => [
  NormalSetting(
    title: '关于',
    icon: Icons.info_outline,
    subtitle: 'MTBBS v${BuildConfig.versionName}+${BuildConfig.versionCode}',
    onTap: (ctx, s) => ctx.push('/settings/about'),
  ),
];
