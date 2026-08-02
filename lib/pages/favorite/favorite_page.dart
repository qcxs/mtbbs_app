import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/api/home/favorite/export.dart' as favorite_api;
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/widgets/layout/load_more_footer.dart';
import 'package:mtbbs/widgets/layout/page_error_widget.dart';
import 'package:mtbbs/widgets/layout/state_views.dart';

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

  /// 正在删除的收藏 ID（用于禁用对应删除按钮）
  String? _deletingFavid;

  /// 二次确认后删除收藏：成功移除条目 + toast，失败 toast 错误
  Future<void> _confirmDelete(Map<String, dynamic> item) async {
    final favid = item['favid']?.toString() ?? '';
    if (favid.isEmpty) return;
    final title = item['title'] as String? ?? '';
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('取消收藏'),
        content: Text('确定要取消收藏「$title」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deletingFavid = favid);
    try {
      final result = await favorite_api.deleteFavorite(
        ApiService().dio,
        favid: favid,
      );
      if (!mounted) return;
      if (result['success'] == true) {
        setState(() {
          _items.removeWhere((e) => e['favid']?.toString() == favid);
          _deletingFavid = null;
        });
        messenger.showSnackBar(
          const SnackBar(
            content: Text('已取消收藏'),
            duration: Duration(seconds: 1),
          ),
        );
      } else {
        setState(() => _deletingFavid = null);
        messenger.showSnackBar(
          SnackBar(content: Text(result['message']?.toString() ?? '删除失败')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      AppLogger.w('PAGE', 'FavoritePage delete error: $e');
      setState(() => _deletingFavid = null);
      messenger.showSnackBar(SnackBar(content: Text('删除失败: $e')));
    }
  }

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
    if (_isLoading) return const LoadingView();

    if (_error != null) {
      return PageErrorWidget(message: _error!, onRetry: _fetch);
    }

    if (_items.isEmpty) {
      return const EmptyView(icon: Icons.bookmark_border, text: '暂无收藏');
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
            itemCount: _items.length + (_isLoadingMore || !_hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= _items.length) {
                return LoadMoreFooter(
                  loading: _isLoadingMore,
                  hasMore: _hasMore,
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
                        Expanded(
                          child: _FavoriteCard(
                            item: _items[i],
                            deleting:
                                _deletingFavid ==
                                _items[i]['favid']?.toString(),
                            onDelete: () => _confirmDelete(_items[i]),
                          ),
                        ),
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
                child: _FavoriteCard(
                  item: _items[index],
                  deleting:
                      _deletingFavid == _items[index]['favid']?.toString(),
                  onDelete: () => _confirmDelete(_items[index]),
                ),
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

  /// 点击删除按钮回调（由父级处理二次确认）
  final VoidCallback? onDelete;

  /// 当前条目是否正在删除（禁用按钮）
  final bool deleting;

  const _FavoriteCard({
    required this.item,
    this.onDelete,
    this.deleting = false,
  });

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
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
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
                  IconButton(
                    icon: deleting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.bookmark_remove_outlined, size: 20),
                    color: cs.error,
                    visualDensity: VisualDensity.compact,
                    tooltip: '取消收藏',
                    onPressed: deleting ? null : onDelete,
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
