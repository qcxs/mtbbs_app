import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mtbbs/core/utils/url_router.dart';
import 'package:mtbbs/core/utils/cache_utils.dart';
import 'package:mtbbs/core/utils/screen_size_ext.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/auth/providers/auth_provider.dart';
import 'package:mtbbs/models/managed_item.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/common/ranklist_section.dart';
import 'package:mtbbs/widgets/common/rss_section.dart';
import 'package:mtbbs/pages/settings/shortcut_links_dialog.dart';
import 'package:mtbbs/pages/settings/forum_management.dart';
import 'package:mtbbs/pages/settings/site_management.dart';

part 'home_page_widgets.dart';

/// 首页
///
/// 结构 = 站点条 + 若干可折叠区块（快捷链接 / 版块 / 帖子排行 / RSS）。
///
/// 区块的顺序、显隐、默认展开状态都来自 `SettingsProvider.homeSections`：
/// 用户在首页当场折叠会写回同一份状态，下次启动保持折叠，不需要两套配置。
///
/// 区块始终单列纵向排列 —— 区块高度由内容决定，强行分成左右两列必然
/// 一边长一边短。宽屏的宽度交给区块**内部**消化：快捷链接按容器宽度
/// 自动加列，版块换行铺开，排行自己双列。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _refreshCounter = 0;

  Future<void> _refreshAll() async {
    setState(() => _refreshCounter++);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final baseUrl = context.select<SiteStore, String>((s) => s.baseUrl);
    final cards = [
      for (final s in settings.visibleHomeSections)
        _buildSection(context, settings, s),
    ];
    // 宽屏只是多留一点边距，避免内容在超宽窗口里贴着边框
    final hPad = MediaQuery.sizeOf(context).isWide ? 24.0 : 12.0;

    return RefreshIndicator(
      key: ValueKey('home_$baseUrl'),
      onRefresh: _refreshAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 24),
        children: [
          const _SiteHeader(),
          const SizedBox(height: 12),
          ..._stacked(cards),
        ],
      ),
    );
  }

  /// 区块之间统一 12px 间距
  List<Widget> _stacked(List<Widget> items) => [
    for (var i = 0; i < items.length; i++) ...[
      if (i > 0) const SizedBox(height: 12),
      items[i],
    ],
  ];

  Widget _buildSection(
    BuildContext context,
    SettingsProvider settings,
    ManagedItem section,
  ) {
    final expanded = SettingsProvider.homeSectionExpanded(section);
    final child = switch (section.id) {
      'shortcuts' => _ShortcutGrid(
        links: settings.shortcutLinks.where((e) => e.visible).toList(),
      ),
      'forums' => const _ForumList(),
      'rank' => RanklistSection(key: ValueKey('rank_$_refreshCounter')),
      'rss' => RssSection(key: ValueKey('rss_$_refreshCounter')),
      _ => const SizedBox.shrink(),
    };

    return _HomeSectionCard(
      title: section.name,
      expanded: expanded,
      onToggle: () => settings.setHomeSectionExpanded(section.id, !expanded),
      trailing: _editButtonFor(context, settings, section.id),
      child: child,
    );
  }

  /// 区块标题右侧的管理入口（快捷链接 / 版块才有）
  Widget? _editButtonFor(
    BuildContext context,
    SettingsProvider settings,
    String id,
  ) {
    return switch (id) {
      'shortcuts' => _SectionEditButton(
        tooltip: '管理快捷链接',
        onPressed: () => ShortcutLinksDialog.show(context, settings),
      ),
      'forums' => _SectionEditButton(
        tooltip: '管理版块',
        onPressed: () => ForumManagement.showPicker(context, settings),
      ),
      _ => null,
    };
  }
}

/// 打开链接：决策统一交给 `UrlRouter.resolveTarget`
/// （App 内路由优先，解析不出或属于其他站点则兜底内置浏览器）
void _openUrl(BuildContext context, String url) {
  final target = UrlRouter.resolveTarget(url);
  if (target != null) context.push(target);
}
