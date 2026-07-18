import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/site_config.dart';
import '../../core/url_router.dart';
import '../../models/managed_item.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/page_actions.dart';
import '../../widgets/ranklist_section.dart';
import '../../widgets/rss_section.dart';

/// 首页
///
/// 分为三部分（均为独立组件）：
///   1. 快捷链接（可配置的图标网格）
///   2. 帖子排行（带 Tab 切换）
///   3. RSS 订阅列表
///
/// 排行和 RSS 各自管理自己的加载状态，通过 key 变更触发刷新。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _refreshCounter = 0;

  Future<void> _refreshAll() {
    setState(() => _refreshCounter++);
    return Future.value();
  }

  String get _homeUrl => SiteConfig.baseUrl;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final links = settings.shortcutLinks.where((e) => e.visible).toList();
    final refreshKey = ValueKey('refresh_$_refreshCounter');

    return Scaffold(
      appBar: AppBar(
        title: Text(SiteConfig.current.name),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: [
          PageActions(
            url: _homeUrl,
            onRefresh: _refreshAll,
            copyLabel: '复制首页链接',
          ),
        ],
      ),
      body: RefreshIndicator(
        key: ValueKey('home_${SiteConfig.baseUrl}'),
        onRefresh: _refreshAll,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // ====== 快捷链接 ======
            if (links.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '快捷链接',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: links
                    .map((link) => _ShortcutTile(link: link))
                    .toList(),
              ),
              const SizedBox(height: 24),
            ],

            // ====== 帖子排行 ======
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '帖子排行',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
            RanklistSection(key: refreshKey),
            const SizedBox(height: 24),

            // ====== RSS 订阅 ======
            RssSection(key: refreshKey),
          ],
        ),
      ),
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
                  context.push('/browser?url=${Uri.encodeComponent(url)}');
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
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: imageUrl != null && imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) =>
                          const Icon(Icons.link, color: Colors.grey),
                    )
                  : Center(
                      child: Text(
                        link.name.length >= 2
                            ? link.name.substring(0, 2)
                            : link.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade500,
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
