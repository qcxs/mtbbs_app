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

/// 打开链接：优先走 App 内路由，匹配不到（或属于其他站点）再交给内置浏览器
void _openUrl(BuildContext context, String url) {
  if (url.isEmpty) return;
  if (url.startsWith('http://') || url.startsWith('https://')) {
    final result = UrlRouter.parse(url);
    if (result.appPath != null && !result.isOtherSite) {
      context.push(result.appPath!);
    } else {
      context.push('/browser?url=${Uri.encodeComponent(url)}&intercept=false');
    }
  } else {
    context.push(url);
  }
}

// ==================== 站点条 ====================

/// 顶部站点标识 — 让首页有明确的"我在哪个论坛"，并承载签到入口。
class _SiteHeader extends StatelessWidget {
  const _SiteHeader();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final auth = context.watch<AuthProvider>();
    final site = SiteStore.instance.current;

    // 签到入口随快捷链接配置走：只有当前站点配了 sign 且已登录时才出现
    final signs = auth.isLoggedIn
        ? settings.shortcutLinks.where((e) => e.id == 'sign' && e.visible)
        : const Iterable<ManagedItem>.empty();
    final signUrl = signs.isEmpty
        ? ''
        : signs.first.data?['url']?.toString() ?? '';

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                site.name.isEmpty ? '?' : site.name.substring(0, 1),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: cs.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    site.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    site.host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (signUrl.isNotEmpty)
              FilledButton.tonalIcon(
                onPressed: () => _openUrl(context, signUrl),
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label: const Text('签到'),
              ),
          ],
        ),
      ),
    );
  }
}

// ==================== 区块卡片 ====================

class _HomeSectionCard extends StatelessWidget {
  const _HomeSectionCard({
    required this.title,
    required this.expanded,
    required this.onToggle,
    required this.child,
    this.trailing,
  });

  final String title;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  /// 标题右侧操作按钮（如管理），点击不触发折叠
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: cs.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  ?trailing,
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 折叠时整棵子树不构建 —— 区块内的网络请求随折叠一起停掉
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: child,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// 分区标题栏右侧的编辑按钮（点击不触发折叠）
class _SectionEditButton extends StatelessWidget {
  const _SectionEditButton({required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.edit_outlined, size: 18),
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: onPressed,
    );
  }
}

// ==================== 快捷链接 ====================

/// 快捷链接网格 — 4 列自适应方格，超过两行的收进「显示全部」
class _ShortcutGrid extends StatefulWidget {
  const _ShortcutGrid({required this.links});

  final List<ManagedItem> links;

  @override
  State<_ShortcutGrid> createState() => _ShortcutGridState();
}

class _ShortcutGridState extends State<_ShortcutGrid> {
  /// 单个入口的目标宽度。列数由容器宽度算出来，所以宽屏会一直加列，
  /// 而不是把每个入口越撑越大。
  static const double _targetTileWidth = 56;
  static const double _spacing = 8;
  static const double _labelHeight = 22;

  bool _showAll = false;

  @override
  void didUpdateWidget(covariant _ShortcutGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 条目增减后回到"两行"初始态，避免残留的展开状态与新数量错位
    if (widget.links.length != oldWidget.links.length) _showAll = false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final links = widget.links;
    if (links.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          '还没有快捷链接，点右上角的管理按钮添加',
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = math.max(
          3,
          (constraints.maxWidth / (_targetTileWidth + _spacing)).ceil(),
        );
        final tileWidth =
            (constraints.maxWidth - _spacing * (columns - 1)) / columns;
        // 首屏铺两行，其余收进「显示全部」
        final initialCount = columns * 2;
        final hasOverflow = links.length > initialCount;
        final shown = _showAll ? links : links.take(initialCount).toList();

        return Column(
          children: [
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: _spacing,
                mainAxisSpacing: 12,
                // 方格 + 文字行，保证图标区是正方形
                childAspectRatio: tileWidth / (tileWidth + _labelHeight),
              ),
              itemCount: shown.length,
              itemBuilder: (_, i) => _ShortcutTile(link: shown[i]),
            ),
            if (hasOverflow)
              TextButton(
                onPressed: () => setState(() => _showAll = !_showAll),
                child: Text(
                  _showAll ? '收起' : '显示全部 ${links.length} 个',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({required this.link});

  final ManagedItem link;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = link.data?['url']?.toString() ?? '';
    final imageUrl = link.data?['imageUrl']?.toString();

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: url.isEmpty ? null : () => _openUrl(context, url),
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                color: cs.surfaceContainerHighest,
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        cacheManager: imageCacheManager,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            Icon(Icons.link, color: cs.onSurfaceVariant),
                      )
                    : Center(
                        child: Text(
                          link.name.length >= 2
                              ? link.name.substring(0, 2)
                              : link.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 16,
            child: Text(
              link.name,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== 版块列表 ====================

class _ForumList extends StatelessWidget {
  const _ForumList();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final forums = SiteStore.instance.defaultForumOrder
        .where((fid) => SiteStore.instance.forums.containsKey(fid))
        .map((fid) => MapEntry(fid, SiteStore.instance.forums[fid]!))
        .toList();
    if (forums.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          '还没有版块，点右上角的管理按钮添加',
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: forums.map((entry) {
        return InkWell(
          onTap: () => context.push('/forum?fid=${entry.key}'),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.forum, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  entry.value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
