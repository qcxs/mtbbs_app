import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../api/home/favorite/export.dart' as favorite_api;
import '../../services/api_service.dart';
import '../../core/logger.dart';
import '../../widgets/page_error_widget.dart';

/// 我的收藏页面
///
/// 分页加载，触底自动加载更多，宽屏自适应多栏。
class FavoritePage extends StatefulWidget {
  const FavoritePage({super.key});

  @override
  State<FavoritePage> createState() => _FavoritePageState();
}

class _FavoritePageState extends State<FavoritePage> {
  final _scrollController = ScrollController();
  final _items = <Map<String, dynamic>>[];
  int _page = 1;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _fetch();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _fetch() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _page = 1;
    });

    try {
      final result = await favorite_api.fetchFavorites(
        ApiService().dio,
        page: 1,
      );
      if (!mounted) return;

      if (result['success'] != true) {
        setState(() {
          _error = result['message'] as String? ?? '加载失败';
          _isLoading = false;
        });
        return;
      }

      final items = (result['items'] as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      setState(() {
        _items
          ..clear()
          ..addAll(items);
        _hasMore = result['hasMore'] as bool;
        _page = 1;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      AppLogger.w('PAGE', 'FavoritePage error: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final nextPage = _page + 1;
      final result = await favorite_api.fetchFavorites(
        ApiService().dio,
        page: nextPage,
      );
      if (!mounted) return;

      if (result['success'] != true) {
        setState(() => _isLoadingMore = false);
        return;
      }

      final items = (result['items'] as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      setState(() {
        _items.addAll(items);
        _hasMore = result['hasMore'] as bool;
        _page = nextPage;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      AppLogger.w('PAGE', 'FavoritePage loadMore error: $e');
      setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的收藏'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetch,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final cs = Theme.of(context).colorScheme;
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return PageErrorWidget(message: _error!, onRetry: _fetch);
    }

    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_border, size: 48, color: cs.outlineVariant),
            const SizedBox(height: 12),
            Text(
              '暂无收藏',
              style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 900
            ? 2
            : constraints.maxWidth >= 600
            ? 2
            : 1;

        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollEndNotification) {
              _onScroll();
            }
            return false;
          },
          child: ListView.builder(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(8),
            itemCount: _items.length + (_isLoadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= _items.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }

              // 多列模式：按行分组
              if (crossAxisCount > 1) {
                if (index % crossAxisCount != 0) return const SizedBox.shrink();
                final rowEnd = (index + crossAxisCount).clamp(0, _items.length);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (int i = index; i < rowEnd; i++) ...[
                        if (i > index) const SizedBox(width: 8),
                        Expanded(child: _FavoriteCard(item: _items[i])),
                      ],
                      if (rowEnd - index < crossAxisCount)
                        ...List.generate(
                          crossAxisCount - (rowEnd - index),
                          (_) => const Expanded(child: SizedBox.shrink()),
                        ),
                    ],
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _FavoriteCard(item: _items[index]),
              );
            },
          ),
        );
      },
    );
  }
}

/// 收藏条目卡片
class _FavoriteCard extends StatelessWidget {
  final Map<String, dynamic> item;

  const _FavoriteCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = item['title'] as String? ?? '';
    final tid = item['tid'] as String? ?? '';
    final time = item['time'] as String? ?? '';
    final note = item['note'] as String? ?? '';
    final type = item['type'] as String? ?? '';

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: tid.isNotEmpty ? () => context.push('/thread/$tid') : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    type == 'thread' ? Icons.article_outlined : Icons.link,
                    size: 14,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (note.isNotEmpty) ...[
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    note,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              if (time.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  time,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
