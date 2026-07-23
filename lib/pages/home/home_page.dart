import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/url_router.dart';
import '../../core/site_store.dart';
import '../../models/managed_item.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/ranklist_section.dart';
import '../../widgets/rss_section.dart';

/// 首页
///
/// 分为四部分（均为独立组件，可折叠）：
///   1. 快捷链接
///   2. 版块列表
///   3. 帖子排行
///   4. RSS 订阅
///
/// 排行和 RSS 默认展开，其余折叠。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _refreshCounter = 0;
  final Set<String> _expandedSections = {'排行', 'RSS'};

  Future<void> _refreshAll() {
    setState(() => _refreshCounter++);
    return Future.value();
  }

  void _toggleSection(String name) {
    setState(() {
      if (_expandedSections.contains(name)) {
        _expandedSections.remove(name);
      } else {
        _expandedSections.add(name);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final siteStore = context.watch<SiteStore>();
    final links = settings.shortcutLinks.where((e) => e.visible).toList();
    final refreshKey = ValueKey('refresh_$_refreshCounter');

    return RefreshIndicator(
      key: ValueKey('home_${siteStore.baseUrl}'),
      onRefresh: _refreshAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          // ====== 快捷链接 ======
          if (links.isNotEmpty) ...[
            _CollapsibleSection(
              title: '快捷链接',
              expanded: _expandedSections.contains('快捷链接'),
              onToggle: () => _toggleSection('快捷链接'),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: links
                    .map((link) => _ShortcutTile(link: link))
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ====== 版块 ======
          _CollapsibleSection(
            title: '版块',
            expanded: _expandedSections.contains('版块'),
            onToggle: () => _toggleSection('版块'),
            child: _ForumList(),
          ),
          const SizedBox(height: 12),

          // ====== 帖子排行 ======
          _CollapsibleSection(
            title: '帖子排行',
            expanded: _expandedSections.contains('排行'),
            onToggle: () => _toggleSection('排行'),
            child: RanklistSection(key: refreshKey),
          ),
          const SizedBox(height: 12),

          // ====== RSS 订阅 ======
          _CollapsibleSection(
            title: 'RSS 订阅',
            expanded: _expandedSections.contains('RSS'),
            onToggle: () => _toggleSection('RSS'),
            child: RssSection(key: refreshKey),
          ),
        ],
      ),
    );
  }
}

// ==================== 可折叠段落 ====================

class _CollapsibleSection extends StatelessWidget {
  final String title;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  const _CollapsibleSection({
    required this.title,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onToggle,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: child,
          secondChild: const SizedBox.shrink(),
          crossFadeState: expanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }
}

// ==================== 快捷链接瓦片 ====================
// 保持内联，因逻辑简单且仅首页使用

class _ShortcutTile extends StatelessWidget {
  final ManagedItem link;
  const _ShortcutTile({required this.link});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = link.data?['url']?.toString() ?? '';
    final imageUrl = link.data?['imageUrl']?.toString();

    return GestureDetector(
      onTap: url.isNotEmpty
          ? () {
              if (url.startsWith('http://') || url.startsWith('https://')) {
                // 优先使用 URL 路由匹配，没有匹配才在内置浏览器中打开
                final routeResult = UrlRouter.parse(url);
                if (routeResult.appPath != null && !routeResult.isOtherSite) {
                  context.push(routeResult.appPath!);
                } else {
                  context.push(
                    '/browser?url=${Uri.encodeComponent(url)}&intercept=false',
                  );
                }
              } else {
                context.push(url);
              }
            }
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: imageUrl != null && imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
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
          const SizedBox(height: 4),
          SizedBox(
            width: 64,
            child: Text(
              link.name,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== 版块列表 ====================

class _ForumList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final forums = SiteStore.instance.defaultForumOrder
        .where((fid) => SiteStore.instance.forums.containsKey(fid))
        .map((fid) => MapEntry(fid, SiteStore.instance.forums[fid]!))
        .toList();
    if (forums.isEmpty) return const SizedBox.shrink();
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
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.surfaceContainerLow),
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
