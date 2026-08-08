import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/pages/settings/models/settings_model.dart';
import 'package:mtbbs/pages/settings/widgets/dialogs.dart';
import 'package:mtbbs/providers/history_provider.dart';
import 'package:provider/provider.dart';

/// 数据与缓存组设置项
List<SettingsModel> dataSettings() => [
  NormalSetting(
    title: '缓存管理',
    subtitle: '头像/表情/预览缓存，设置过期时间',
    icon: Icons.storage,
    onTap: (ctx, s) => ctx.push('/settings/cache'),
  ),
  NormalSetting(
    title: '表情管理',
    subtitle: '查看和刷新当前站点表情',
    icon: Icons.emoji_emotions,
    onTap: (ctx, s) => ctx.push('/settings/emoji'),
  ),
  NormalSetting(
    title: 'MT 图床管理',
    subtitle: '查看和管理 MT 图床图片',
    icon: Icons.photo_library,
    onTap: (ctx, s) => ctx.push('/settings/mt-images'),
  ),
  NormalSetting(
    title: '浏览历史最大记录数',
    icon: Icons.history,
    subtitleBuilder: (s) => '${s.historyMaxCount} 条',
    onTap: (ctx, s) => showNumberDialog(
      context: ctx,
      title: '最大记录数',
      description: '设置浏览历史最多保存多少条记录（10-1000）。',
      initValue: s.historyMaxCount,
      min: 10,
      max: 1000,
      helperText: '默认 200',
      onSave: (v) async {
        await s.setHistoryMaxCount(v);
        ctx.read<HistoryProvider>().setMaxCount(v);
      },
    ),
  ),
];
