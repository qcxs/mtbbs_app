import 'package:flutter/material.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/pages/settings/forum_management.dart';
import 'package:mtbbs/pages/settings/formula_dialog.dart';
import 'package:mtbbs/pages/settings/models/settings_model.dart';
import 'package:mtbbs/pages/settings/shortcut_links_dialog.dart';
import 'package:mtbbs/pages/settings/site_management.dart';
import 'package:mtbbs/pages/settings/user_management_dialog.dart';
import 'package:mtbbs/pages/settings/widgets/dialogs.dart';
import 'package:mtbbs/providers/settings_provider.dart';

/// 站点组设置项
List<SettingsModel> siteSettings() => [
  NormalSetting(
    title: '当前站点',
    icon: Icons.dns,
    subtitleBuilder: (s) => SiteStore.instance.sites[s.currentSiteIndex].name,
    onTap: (ctx, s) => SiteManagement.showPicker(ctx, s),
  ),
  NormalSetting(
    title: '用户管理',
    subtitle: '账号切换、导入导出、清除登录信息',
    icon: Icons.person,
    onTap: (ctx, s) =>
        showDialog(context: ctx, builder: (_) => const UserManagementDialog()),
  ),
  NormalSetting(
    title: '浏览模式',
    subtitleBuilder: (s) => SiteStore.instance.isMobileUA ? '移动版（推荐）' : '桌面版',
    icon: Icons.phone_android,
    onTap: (ctx, s) => _showUADialog(ctx, s),
  ),
  NormalSetting(
    title: '版块管理',
    icon: Icons.forum,
    subtitleBuilder: (s) => '${s.forumEntries.length} 个板块',
    onTap: (ctx, s) => ForumManagement.showPicker(ctx, s),
  ),
  NormalSetting(
    title: '积分公式',
    subtitle: '点击查看和刷新',
    icon: Icons.calculate,
    onTap: (ctx, s) => FormulaDialog.show(ctx, s),
  ),
  NormalSetting(
    title: '管理快捷链接',
    icon: Icons.link,
    subtitleBuilder: (s) => '${s.shortcutLinks.length} 个链接',
    onTap: (ctx, s) => ShortcutLinksDialog.show(ctx, s),
  ),
];

Future<void> _showUADialog(
  BuildContext context,
  SettingsProvider settings,
) async {
  final isMobile = SiteStore.instance.isMobileUA;
  final picked = await showSelectDialog<String>(
    context: context,
    title: '浏览模式',
    options: [
      SelectOption(
        value: Site.uaAndroid,
        icon: Icons.phone_android,
        label: '移动版',
        description: '使用手机 UA 访问，克米模板卡片式布局，默认推荐',
      ),
      SelectOption(
        value: Site.uaPc,
        icon: Icons.desktop_windows,
        label: '桌面版',
        description: '使用电脑 UA 访问，标准 Discuz 表格布局',
      ),
    ],
    selected: isMobile ? Site.uaAndroid : Site.uaPc,
  );
  if (picked != null) await settings.setSiteUA(picked);
}
