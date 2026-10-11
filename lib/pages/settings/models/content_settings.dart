import 'package:flutter/material.dart';
import 'package:mtbbs/config/notice_config.dart';
import 'package:mtbbs/pages/settings/bbcode_dialog.dart';
import 'package:mtbbs/pages/settings/models/settings_model.dart';
import 'package:mtbbs/pages/settings/widgets/dialogs.dart';
// 直接导入：扩展方法（noticeBadgeMode 等 accessor/setter）只在**直接**导入的库里可见
import 'package:mtbbs/providers/settings_provider.dart';

/// 阅读与渲染组设置项
List<SettingsModel> contentSettings() => [
  NormalSetting(
    title: '正文字号',
    icon: Icons.format_size,
    subtitleBuilder: (s) => '${s.fontSize.round()}px，默认 16px',
    onTap: (ctx, s) => showNumberDialog(
      context: ctx,
      title: '正文字号',
      description:
          '帖子正文的基准字号（12-32px），引用与代码块同步；'
          '与系统字体大小叠加生效。',
      initValue: s.fontSize.round(),
      min: 12,
      max: 32,
      helperText: '默认 16px',
      onSave: (v) => s.setFontSize(v.toDouble()),
    ),
  ),
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
    title: '消息未读标记',
    icon: Icons.badge_outlined,
    subtitleBuilder: (s) => '当前标记样式：${s.noticeBadgeMode.desc}',
    onTap: (ctx, s) async {
      final r = await showSelectDialog<NoticeBadgeMode>(
        context: ctx,
        title: '消息未读标记',
        selected: s.noticeBadgeMode,
        options: [
          for (final m in NoticeBadgeMode.values)
            SelectOption(value: m, label: m.desc),
        ],
      );
      if (r != null) await s.setNoticeBadgeMode(r);
    },
  ),
  NormalSetting(
    title: '计入未读的分组',
    icon: Icons.filter_alt_outlined,
    subtitleBuilder: (s) {
      final picked = s.noticeBadgeGroups;
      if (picked.isEmpty) return '未选择（不显示数字）';
      if (picked.length == noticeGroups.length) return '全部分组';
      return noticeGroups
          .where((g) => picked.contains(g.id))
          .map((g) => g.label)
          .join('、');
    },
    onTap: (ctx, s) async {
      final r = await showMultiSelectDialog<String>(
        context: ctx,
        title: '计入未读的分组',
        selected: s.noticeBadgeGroups,
        options: [
          for (final g in noticeGroups)
            SelectOption(value: g.id, label: g.label),
        ],
      );
      if (r != null) await s.setNoticeBadgeGroups(r);
    },
  ),
  SwitchSetting(
    title: '检查新提醒',
    subtitle: '回前台 / 切到消息页时检查未读（最多 5 分钟一次）',
    icon: Icons.notifications_active_outlined,
    value: (s) => s.noticeCheckEnabled,
    onChanged: (ctx, s, v) => s.setNoticeCheckEnabled(v),
  ),
];
