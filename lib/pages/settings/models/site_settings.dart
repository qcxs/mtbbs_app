import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/core/app/app_page_gate.dart';
import 'package:mtbbs/core/app/session_registry.dart';
import 'package:mtbbs/core/app/site_cdn.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/pages/settings/cdn_dialog.dart';
import 'package:mtbbs/pages/settings/emoji_management.dart';
import 'package:mtbbs/pages/settings/forum_management.dart';
import 'package:mtbbs/pages/settings/formula_dialog.dart';
import 'package:mtbbs/pages/settings/models/settings_model.dart';
import 'package:mtbbs/pages/settings/shortcut_links_dialog.dart';
import 'package:mtbbs/pages/settings/site_management.dart';
import 'package:mtbbs/pages/settings/user_management_dialog.dart';
import 'package:mtbbs/pages/settings/widgets/dialogs.dart';
import 'package:mtbbs/providers/settings_provider.dart';

/// 站点设置组：所有项只对**当前站点**生效。
List<SettingsModel> siteSettings() => [
  const HeaderSetting(title: '站点与访问', subtitle: '以下设置仅对当前站点生效'),
  NormalSetting(
    title: '当前站点',
    icon: Icons.dns,
    subtitleBuilder: (s) => SiteStore.instance.sites[s.currentSiteIndex].name,
    onTap: (ctx, s) => SiteManagement.showPicker(ctx, s),
  ),
  NormalSetting(
    title: '浏览模式',
    subtitleBuilder: (s) => SiteStore.instance.isMobileUA ? '移动版（推荐）' : '桌面版',
    icon: Icons.phone_android,
    onTap: (ctx, s) => _showUADialog(ctx, s),
  ),
  NormalSetting(
    title: 'CDN 检测',
    subtitleBuilder: (s) {
      final detected = SiteCdnStore.instance.cdnFor(SiteStore.instance.host);
      return detected ?? '未识别，当前使用站点地址';
    },
    icon: Icons.cloud_sync,
    onTap: (ctx, s) => CdnDialog.show(ctx),
  ),
  SwitchSetting(
    title: '模拟浏览器请求头',
    subtitle: 'API 与图片请求携带 Referer / Accept；关闭后部分站点可能拒绝访问',
    icon: Icons.travel_explore,
    value: (s) => s.simulateBrowserHeaders,
    onChanged: (ctx, s, v) => s.setSimulateBrowserHeaders(v),
  ),
  SwitchSetting(
    title: '人机验证自动处理',
    subtitle: '站点返回验证页 / 防火墙拦截页时自动弹出浏览器，通过后自动继续请求',
    icon: Icons.verified_user,
    value: (s) => s.interstitialAutoVerify,
    onChanged: (ctx, s, v) => s.setInterstitialAutoVerify(v),
  ),
  NormalSetting(
    title: '版块管理',
    icon: Icons.forum,
    subtitleBuilder: (s) => '${s.forumEntries.length} 个板块',
    onTap: (ctx, s) => ForumManagement.showPicker(ctx, s),
  ),
  const HeaderSetting(title: '内容与工具'),
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
  NormalSetting(
    title: '站点字数限制',
    icon: Icons.text_fields,
    subtitleBuilder: (s) => '${s.postMaxLength} 字（编辑器 / 留言板共用）',
    onTap: (ctx, s) => showNumberDialog(
      context: ctx,
      title: '站点字数限制',
      description:
          '站点允许的单帖 / 留言最大字数。Discuz 默认 65535；不同站点可能不同，'
          '超限内容会被服务端截断。编辑器与留言板均按此值限制。',
      initValue: s.postMaxLength,
      min: 1,
      max: 1000000,
      helperText: '默认 65535',
      onSave: (v) => s.setPostMaxLength(v),
    ),
  ),
  NormalSetting(
    title: '个人空间数据源',
    icon: Icons.source_outlined,
    subtitleBuilder: (s) => switch (s.spaceSource) {
      'mobile' => '移动版',
      'desktop' => '桌面版',
      _ => '跟随浏览模式',
    },
    onTap: (ctx, s) async {
      final picked = await showSelectDialog<String>(
        context: ctx,
        title: '个人空间数据源',
        selected: s.spaceSource,
        options: const [
          SelectOption(value: '', label: '跟随浏览模式'),
          SelectOption(value: 'mobile', label: '移动版'),
          SelectOption(value: 'desktop', label: '桌面版'),
        ],
      );
      if (picked != null) await s.setSpaceSource(picked);
    },
  ),
  NormalSetting(
    title: '表情管理',
    icon: Icons.emoji_emotions,
    onTap: (ctx, s) => showEmojiManagementSheet(ctx),
  ),
  const HeaderSetting(title: '身份'),
  NormalSetting(
    title: '默认用户',
    icon: Icons.person_pin_circle_outlined,
    subtitleBuilder: (s) =>
        SessionRegistry.instance.defaultAccountFor(SiteStore.instance.host) ??
        '游客（未登录）',
    onTap: (ctx, s) => ctx.push('/settings/users'),
  ),
  const HeaderSetting(title: '页面接管', subtitle: '关闭某项后，该页面在本站点改用内置浏览器打开'),
  SwitchSetting(
    title: '本站点全部改用内置浏览器',
    subtitle:
        '逃生阀：开启后本站点不再使用 App 页面，所有跳转都用内置浏览器打开。'
        '若被锁在浏览器里，可从浏览器右上角「设置」入口关回来',
    icon: Icons.travel_explore,
    value: (s) => s.browserOnlyMode,
    onChanged: (ctx, s, v) => s.setBrowserOnlyMode(v),
  ),
  for (final page in appPages)
    SwitchSetting(
      title: page.label,
      icon: page.icon,
      value: (s) => s.isAppPageEnabled(page.id),
      onChanged: (ctx, s, v) => s.setAppPageEnabled(page.id, v),
    ),
];

/// 账号设置组（账号级偏好暂未引入，先保留账号管理入口）
List<SettingsModel> accountSettings() => [
  const HeaderSetting(title: '账号设置', subtitle: '账号级行为后续在这里扩展；默认用户是站点设置，不在此处'),
  NormalSetting(
    title: '用户管理',
    subtitle: '账号切换、导入导出、清除登录信息',
    icon: Icons.person,
    onTap: (ctx, s) =>
        showDialog(context: ctx, builder: (_) => const UserManagementDialog()),
  ),
  NormalSetting(
    title: '用户设置',
    subtitle: '按账号设置跨站身份与行为（如默认用户）',
    icon: Icons.manage_accounts_outlined,
    onTap: (ctx, s) => ctx.push('/settings/users'),
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
