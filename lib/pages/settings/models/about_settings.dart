import 'package:flutter/material.dart';
import 'package:mtbbs/config/build_config.dart';
import 'package:mtbbs/core/app/stagger_queue.dart';
import 'package:mtbbs/pages/settings/models/settings_model.dart';
import 'package:mtbbs/pages/settings/widgets/dialogs.dart';

/// 关于组设置项
List<SettingsModel> aboutSettings() => [
  NormalSetting(
    title: '通用错峰间隔',
    icon: Icons.motion_photos_on,
    subtitleBuilder: (s) => '${s.staggerInterval}ms，批量请求逐个放行',
    onTap: (ctx, s) => showNumberDialog(
      context: ctx,
      title: '通用错峰间隔',
      description: '短时间大量请求时，可能封ip，设置请求间隔，主动放慢请求。取值范围：（20-300ms），自行测试。',
      initValue: s.staggerInterval,
      min: 20,
      max: 300,
      helperText: '默认 40ms',
      onSave: (v) async {
        await s.setStaggerInterval(v);
        setStaggerInterval(Duration(milliseconds: v));
      },
    ),
  ),
  NormalSetting(
    title: '关于',
    icon: Icons.info_outline,
    subtitle: 'MTBBS v${BuildConfig.versionName}+${BuildConfig.versionCode}',
    onTap: (ctx, s) {},
  ),
];
