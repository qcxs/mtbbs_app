import 'package:flutter/material.dart';
import '../api/forum/ranklist/export.dart' as ranklist_api;
import '../services/api_service.dart';
import 'rank_tile.dart';

/// 帖子排行区块
///
/// 自带 Tab 切换（回复排行/查看排行/热度排行），懒加载数据。
/// 父页面通过更改 key 触发重新加载。
class RanklistSection extends StatefulWidget {
  const RanklistSection({super.key});

  @override
  State<RanklistSection> createState() => _RanklistSectionState();
}

class _RanklistSectionState extends State<RanklistSection>
    with AutomaticKeepAliveClientMixin {
  static const _views = ['replies', 'views', 'heats'];
  static const _labels = ['回复排行', '查看排行', '热度排行'];

  int _tabIndex = 0;
  static final Map<int, List<Map<String, dynamic>>> _items = {};
  static final Map<int, bool> _loading = {};
  static final Map<int, String?> _error = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    updateKeepAlive();
    debugPrint(
      '[RanklistSection] initState called, _items isEmpty=${_items.isEmpty}',
    );
    _fetch(tab: 0);
  }

  @override
  void didUpdateWidget(covariant RanklistSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // key 改变时（父页面主动触发刷新），重新加载
    if (widget.key != oldWidget.key) {
      _items.clear();
      _loading.clear();
      _error.clear();
      _fetch(tab: _tabIndex, force: true);
    }
  }

  Future<void> _fetch({required int tab, bool force = false}) async {
    if (_items.containsKey(tab) && !force) return;
    setState(() {
      _loading[tab] = true;
      _error[tab] = null;
    });
    try {
      final view = _views[tab];
      final result = await ranklist_api.getRanklist(
        ApiService().dio,
        view: view,
        orderby: 'thisweek',
      );
      if (!mounted) return;
      if (result['success'] == true) {
        setState(() {
          _items[tab] = List<Map<String, dynamic>>.from(result['items'] ?? []);
          _loading[tab] = false;
        });
      } else {
        setState(() {
          _error[tab] = result['message']?.toString() ?? '获取排行失败';
          _loading[tab] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error[tab] = e.toString();
          _loading[tab] = false;
        });
      }
    }
  }

  void _onTabChanged(int index) {
    if (index == _tabIndex) return;
    setState(() => _tabIndex = index);
    if (!_items.containsKey(index) && !(_loading[index] ?? false)) {
      _fetch(tab: index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tab 切换栏
        SizedBox(
          height: 32,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _views.length,
            separatorBuilder: (_, __) => const SizedBox(width: 4),
            itemBuilder: (_, i) {
              final isActive = i == _tabIndex;
              return GestureDetector(
                onTap: () => _onTabChanged(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: isActive
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _labels[i],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isActive
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: isActive ? Colors.white : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        _buildList(),
      ],
    );
  }

  Widget _buildList() {
    final cs = Theme.of(context).colorScheme;
    final tab = _tabIndex;
    final loading = _loading[tab] ?? false;
    final error = _error[tab];
    final items = _items[tab];

    if (loading && (items == null || items.isEmpty)) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (error != null && (items == null || items.isEmpty)) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.trending_up, size: 32, color: cs.outlineVariant),
              const SizedBox(height: 6),
              Text(
                '加载失败',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
              Text(
                error,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => _fetch(tab: tab),
                icon: const Icon(Icons.refresh, size: 14),
                label: const Text('重试', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      );
    }

    if (items == null || items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text('暂无数据', style: TextStyle(color: cs.onSurfaceVariant)),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;
        final tiles = items.take(10).map((item) {
          return RankTile(
            rank: item['rank'] as int? ?? 0,
            title: item['title']?.toString() ?? '',
            forumName: item['forumName']?.toString() ?? '',
            author: item['author']?.toString() ?? '',
            time: item['time']?.toString() ?? '',
            count: item['count']?.toString() ?? '',
            tid: item['tid']?.toString() ?? '',
          );
        }).toList();

        if (isWide) {
          return Wrap(
            spacing: 8,
            runSpacing: 4,
            children: tiles
                .map(
                  (t) =>
                      SizedBox(width: (constraints.maxWidth - 8) / 2, child: t),
                )
                .toList(),
          );
        }

        return Column(children: tiles);
      },
    );
  }
}
