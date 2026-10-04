import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mtbbs/api/group/groupindex/export.dart' as group_api;
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/utils/cache_utils.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/widgets/common/page_actions.dart';
import 'package:mtbbs/widgets/layout/page_error_widget.dart';
import 'package:mtbbs/widgets/layout/state_views.dart';

/// 圈子首页：推荐圈子 + 圈子分类 + 积分排行
///
/// 路径: /groups
/// 数据源: `group.php?hot=yes`（桌面模板，游客可访问）。
/// 点分类 → /groups/category；点圈子 → /groups/content（只读讨论区）。
///
/// MT 圈子基本废弃，各区块都可能为空，空态统一用 [EmptyView] 兜住。
class GroupIndexPage extends StatefulWidget {
  const GroupIndexPage({super.key});

  @override
  State<GroupIndexPage> createState() => _GroupIndexPageState();
}

class _GroupIndexPageState extends State<GroupIndexPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _featured = [];
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _rank = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await group_api.fetchGroupIndex(ApiService().dio);
      if (!mounted) return;
      if (r['success'] != true) {
        setState(() {
          _error = r['message'] as String? ?? '加载失败';
          _loading = false;
        });
        return;
      }
      setState(() {
        _featured = _asList(r['featured']);
        _categories = _asList(r['categories']);
        _rank = _asList(r['rank']);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      AppLogger.w('PAGE', 'GroupIndexPage error: $e');
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  static List<Map<String, dynamic>> _asList(Object? v) => (v as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('圈子'),
        surfaceTintColor: cs.surface,
        elevation: 0.5,
        actions: [
          PageActions(
            url: '${SiteStore.instance.baseUrl}/group.php',
            onRefresh: _fetch,
            loading: _loading,
            copyLabel: '复制圈子链接',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return PageErrorWidget(message: _error!, onRetry: _fetch);
    }
    if (_featured.isEmpty && _categories.isEmpty && _rank.isEmpty) {
      return const EmptyView(icon: Icons.groups_outlined, text: '暂无圈子');
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (_featured.isNotEmpty) ...[
          const _SectionHeader('推荐圈子'),
          _buildFeatured(),
        ],
        if (_categories.isNotEmpty) ...[
          const _SectionHeader('圈子分类'),
          ..._categories.map(_buildCategoryTile),
        ],
        if (_rank.isNotEmpty) ...[
          const _SectionHeader('积分排行'),
          ..._rank.asMap().entries.map(
            (e) => _buildRankRow(e.key + 1, e.value),
          ),
        ],
      ],
    );
  }

  Widget _buildFeatured() {
    return SizedBox(
      height: 168,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _featured.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) => _FeaturedCard(item: _featured[i]),
      ),
    );
  }

  Widget _buildCategoryTile(Map<String, dynamic> c) {
    final cs = Theme.of(context).colorScheme;
    final name = c['name'] as String? ?? '';
    final count = c['count'] as int? ?? 0;
    final gid = c['gid'] as String? ?? '';
    return ListTile(
      leading: Icon(Icons.category_outlined, color: cs.primary),
      title: Text(name),
      subtitle: Text('$count 个圈子'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        final q = Uri(
          queryParameters: {'gid': gid, 'name': name},
        ).query;
        context.push('/groups/category?$q');
      },
    );
  }

  Widget _buildRankRow(int rank, Map<String, dynamic> g) {
    final cs = Theme.of(context).colorScheme;
    final name = g['name'] as String? ?? '';
    final score = g['score'] as int? ?? 0;
    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 28,
        child: Text(
          '$rank',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: rank <= 3 ? cs.primary : cs.onSurfaceVariant,
          ),
        ),
      ),
      title: Text(name),
      trailing: Text(
        '$score',
        style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
      ),
      onTap: () => _openGroup(g),
    );
  }

  void _openGroup(Map<String, dynamic> g) {
    final gid = g['gid'] as String? ?? '';
    final name = g['name'] as String? ?? '';
    if (gid.isEmpty) return;
    final q = Uri(queryParameters: {'gid': gid, 'name': name}).query;
    context.push('/groups/content?$q');
  }
}

/// 推荐圈子卡片（图标 + 名称 + 简介）
class _FeaturedCard extends StatelessWidget {
  final Map<String, dynamic> item;

  const _FeaturedCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = item['name'] as String? ?? '';
    final icon = item['icon'] as String? ?? '';
    final desc = item['description'] as String? ?? '';
    final gid = item['gid'] as String? ?? '';

    return SizedBox(
      width: 150,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0.5,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          onTap: () {
            if (gid.isEmpty) return;
            final q = Uri(queryParameters: {'gid': gid, 'name': name}).query;
            context.push('/groups/content?$q');
          },
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: icon.isEmpty
                        ? Icon(Icons.groups, color: cs.onSurfaceVariant)
                        : CachedNetworkImage(
                            imageUrl: icon,
                            cacheManager: imageCacheManager,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) =>
                                Icon(Icons.groups, color: cs.onSurfaceVariant),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 区块标题
class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}
