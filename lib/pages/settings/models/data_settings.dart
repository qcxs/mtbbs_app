import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/pages/settings/models/settings_model.dart';
import 'package:mtbbs/pages/settings/mt_image_manage_sheet.dart';
import 'package:mtbbs/pages/settings/widgets/dialogs.dart';
import 'package:mtbbs/providers/history_provider.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:provider/provider.dart';

/// 存储与工具组设置项
List<SettingsModel> dataSettings() => [
  NormalSetting(
    title: '缓存管理',
    subtitle: '头像/表情/预览缓存，设置过期时间',
    icon: Icons.storage,
    onTap: (ctx, s) => ctx.push('/settings/cache'),
  ),
  NormalSetting(
    title: '帖子缓存',
    subtitle: '自动缓存与离线帖子，支持导入导出和损坏恢复',
    icon: Icons.forum_outlined,
    onTap: (ctx, s) => ctx.push('/settings/cache/threads'),
  ),
  NormalSetting(
    title: 'MT 图床管理',
    subtitle: '查看和管理 MT 图床图片',
    icon: Icons.photo_library,
    onTap: (ctx, s) => showMtImageManageSheet(ctx),
  ),
  NormalSetting(
    title: '通用错峰间隔',
    icon: Icons.motion_photos_on,
    subtitleBuilder: (s) => '${s.staggerInterval}ms，批量请求逐个放行',
    onTap: (ctx, s) => showNumberDialog(
      context: ctx,
      title: '通用错峰间隔',
      description: '短时间大量请求时可能封 IP；设置请求间隔，主动放慢请求。',
      initValue: s.staggerInterval,
      min: 20,
      max: 300,
      helperText: '默认 40ms',
      onSave: (v) => s.setStaggerInterval(v),
    ),
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
