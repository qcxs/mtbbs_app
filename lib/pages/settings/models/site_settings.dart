import 'package:flutter/material.dart';
import 'package:mtbbs/core/app/site_cdn.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/app/stagger_queue.dart';
import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/pages/settings/forum_management.dart';
import 'package:mtbbs/pages/settings/formula_dialog.dart';
import 'package:mtbbs/pages/settings/models/settings_model.dart';
import 'package:mtbbs/pages/settings/shortcut_links_dialog.dart';
import 'package:mtbbs/pages/settings/site_management.dart';
import 'package:mtbbs/pages/settings/user_management_dialog.dart';
import 'package:mtbbs/pages/settings/widgets/dialogs.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';

/// 站点与网络组设置项
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
    title: 'CDN 检测',
    subtitleBuilder: (s) {
      final detected = SiteCdnStore.instance.cdnFor(SiteStore.instance.host);
      return detected ?? '未识别，当前使用站点地址';
    },
    icon: Icons.cloud_sync,
    onTap: (ctx, s) => _refreshCdn(ctx),
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
];

/// 重新识别当前站点 CDN（用户无需配置，识别结果自动用于表情 / 静态图片）
Future<void> _refreshCdn(BuildContext context) async {
  showToast('正在检测 CDN…', duration: const Duration(seconds: 1));
  final cdn = await detectSiteCdn(host: SiteStore.instance.host, force: true);
  if (!context.mounted) return;
  showToast(cdn == null ? '未识别到 CDN，继续使用站点地址' : 'CDN: $cdn');
}

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
