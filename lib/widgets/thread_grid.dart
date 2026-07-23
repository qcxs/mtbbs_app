import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';
import '../controllers/thread_list_controller.dart';
import '../models/thread_item.dart';
import '../models/thread_detail.dart';
import 'thread_card.dart';

/// 通用帖子列表网格
///
/// 功能：
/// - 下拉刷新
/// - 分页器（上一页 / 页码 / 下一页），切换时滚动到顶部
/// - 响应式列数（手机 1 列，平板 2 列，桌面 3 列）
/// - 加载中骨架屏
/// - 空状态、错误状态显示
class ThreadGrid extends StatefulWidget {
  final ThreadListController controller;
  final bool visible;
  final void Function(ThreadItem item)? onViewReplies;
  final Map<int, List<PostItem>> expandedReplies;
  final Set<int> loadingReplies;
  final Map<int, String> errorReplies;

  const ThreadGrid({
    super.key,
    required this.controller,
    this.visible = true,
    this.onViewReplies,
    this.expandedReplies = const {},
    this.loadingReplies = const {},
    this.errorReplies = const {},
  });

  @override
  State<ThreadGrid> createState() => _ThreadGridState();
}

class _ThreadGridState extends State<ThreadGrid>
    with AutomaticKeepAliveClientMixin {
  bool _everLoaded = false;
  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onStateChanged);
  }

  @override
  void didUpdateWidget(ThreadGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onStateChanged);
      widget.controller.addListener(_onStateChanged);
    }
    if (!oldWidget.visible && widget.visible) {
      _checkLoad();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.visible) {
      _checkLoad();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onStateChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _checkLoad() {
    if (_everLoaded) return;
    if (widget.controller.state == LoadState.initial) {
      _everLoaded = true;
      widget.controller.loadInitial();
    }
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  /// 页面切换时滚动到顶部
  void _handlePageChange() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ctrl = widget.controller;

    if (ctrl.state == LoadState.error) {
      return RefreshIndicator(
        onRefresh: ctrl.refresh,
        child: LayoutBuilder(
          builder: (_, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: constraints.maxHeight > 0 ? constraints.maxHeight : null,
              child: _buildError(ctrl),
            ),
          ),
        ),
      );
    }

    if (ctrl.state == LoadState.initial ||
        (ctrl.state == LoadState.loading && ctrl.items.isEmpty)) {
      return _buildSkeleton();
    }

    if (ctrl.items.isEmpty) {
      final cs = Theme.of(context).colorScheme;
      return Stack(
        children: [
          RefreshIndicator(
            onRefresh: ctrl.refresh,
            child: LayoutBuilder(
              builder: (_, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: constraints.maxHeight > 0
                      ? constraints.maxHeight
                      : null,
                  child: _buildEmpty(cs),
                ),
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: _buildFloatingPaginator(ctrl, cs),
          ),
        ],
      );
    }

    return _buildGrid(ctrl);
  }

  // ==================== 响应式列数 ====================

  int _crossAxisCount(double width) {
    if (width >= 900) return 3;
    if (width >= 600) return 2;
    return 1;
  }

  double _gridSpacing(double width) {
    return width >= 600 ? 8 : 0;
  }

  // ==================== 内容区域 ====================

  Widget _buildGrid(ThreadListController ctrl) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = _crossAxisCount(constraints.maxWidth);
        final spacing = _gridSpacing(constraints.maxWidth);
        final cs = Theme.of(context).colorScheme;

        return Stack(
          children: [
            RefreshIndicator(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              onRefresh: ctrl.refresh,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (crossAxisCount == 1)
                    _buildListSliver(ctrl)
                  else
                    _buildGridSliver(ctrl, crossAxisCount, spacing),
                ],
              ),
            ),
            // 悬浮翻页按钮
            Positioned(
              right: 16,
              bottom: 16,
              child: _buildFloatingPaginator(ctrl, cs),
            ),
          ],
        );
      },
    );
  }

  // ==================== 单列列表 ====================

  Widget _buildListSliver(ThreadListController ctrl) {
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final item = ctrl.items[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ThreadCard(
            item: item,
            onTap: () {
              final tid = item.threadId;
              if (tid != null && tid > 0) context.push('/thread/$tid');
            },
            onViewReplies: widget.onViewReplies != null
                ? () => widget.onViewReplies!(item)
                : null,
            replies: widget.expandedReplies[item.threadId],
            repliesLoading: widget.loadingReplies.contains(item.threadId),
            replyError: widget.errorReplies[item.threadId],
          ),
        );
      }, childCount: ctrl.items.length),
    );
  }

  // ==================== 多列网格 ====================

  Widget _buildGridSliver(
    ThreadListController ctrl,
    int crossAxisCount,
    double spacing,
  ) {
    return SliverPadding(
      padding: EdgeInsets.all(spacing),
      sliver: SliverMasonryGrid.count(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        itemBuilder: (context, index) {
          final item = ctrl.items[index];
          return ThreadCard(
            item: item,
            onTap: () {
              final tid = item.threadId;
              if (tid != null && tid > 0) context.push('/thread/$tid');
            },
            onViewReplies: widget.onViewReplies != null
                ? () => widget.onViewReplies!(item)
                : null,
            replies: widget.expandedReplies[item.threadId],
            repliesLoading: widget.loadingReplies.contains(item.threadId),
            replyError: widget.errorReplies[item.threadId],
          );
        },
        childCount: ctrl.items.length,
      ),
    );
  }

  // ==================== 悬浮翻页按钮 ====================

  Widget _buildFloatingPaginator(ThreadListController ctrl, ColorScheme cs) {
    final pageLabel = '第 ${ctrl.page} 页';

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(24),
      color: cs.surface,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pageBtn(
              icon: Icons.chevron_left,
              enabled: ctrl.hasPrev,
              onTap: () {
                ctrl.prevPage();
                _handlePageChange();
              },
              cs: cs,
            ),
            Container(width: 1, height: 20, color: cs.outlineVariant),
            GestureDetector(
              onTap: () => _showPagePicker(ctrl),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: ctrl.state == LoadState.loading
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.onSurfaceVariant,
                        ),
                      )
                    : Text(
                        pageLabel,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
            ),
            Container(width: 1, height: 20, color: cs.outlineVariant),
            _pageBtn(
              icon: Icons.chevron_right,
              enabled: ctrl.hasNext,
              onTap: () {
                ctrl.nextPage();
                _handlePageChange();
              },
              cs: cs,
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageBtn({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
    required ColorScheme cs,
  }) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        icon: Icon(icon, size: 20),
        onPressed: enabled ? onTap : null,
        color: enabled ? cs.onSurfaceVariant : cs.outlineVariant,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      ),
    );
  }

  void _showPagePicker(ThreadListController ctrl) {
    final tc = TextEditingController();
    final knownTotal = ctrl.totalPages > 0;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('跳转页'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                knownTotal
                    ? '共 ${ctrl.totalPages} 页，当前第 ${ctrl.page} 页'
                    : '当前第 ${ctrl.page} 页',
              ),
              const SizedBox(height: 8),
              TextField(
                controller: tc,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: '输入页码',
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final p = int.tryParse(tc.text);
              if (p != null && p >= 1) {
                Navigator.of(ctx).pop();
                ctrl.goToPage(p);
                _handlePageChange();
              }
            },
            child: const Text('跳转'),
          ),
        ],
      ),
    );
  }

  // ==================== 骨架屏 ====================

  Widget _buildSkeleton() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = _crossAxisCount(constraints.maxWidth);
        final spacing = _gridSpacing(constraints.maxWidth);
        final cs = Theme.of(context).colorScheme;

        return RefreshIndicator(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          onRefresh: widget.controller.refresh,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (crossAxisCount == 1)
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: _buildSkeletonCard(cs),
                    ),
                    childCount: 8,
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.all(spacing),
                  sliver: SliverMasonryGrid.count(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: spacing,
                    crossAxisSpacing: spacing,
                    itemBuilder: (context, index) => _buildSkeletonCard(cs),
                    childCount: 8,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSkeletonCard(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Card(
        elevation: 0.5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _skeletonBox(cs, 28, 28, 14),
                  const SizedBox(width: 6),
                  _skeletonBox(cs, 80, 12, 4),
                  const Spacer(),
                  _skeletonBox(cs, 50, 10, 4),
                ],
              ),
              const SizedBox(height: 10),
              _skeletonBox(cs, double.infinity, 16, 4),
              const SizedBox(height: 4),
              _skeletonBox(cs, double.infinity, 12, 4),
              const SizedBox(height: 8),
              _skeletonBox(cs, double.infinity, 100, 6),
              const SizedBox(height: 8),
              Row(
                children: [
                  _skeletonBox(cs, 40, 12, 4),
                  const SizedBox(width: 12),
                  _skeletonBox(cs, 40, 12, 4),
                  const SizedBox(width: 12),
                  _skeletonBox(cs, 40, 12, 4),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _skeletonBox(ColorScheme cs, double w, double h, double r) {
    return Container(
      width: w == double.infinity ? null : w,
      height: h,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(r),
      ),
    );
  }

  // ==================== 空状态 / 错误状态 ====================

  Widget _buildEmpty(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 48, color: cs.outlineVariant),
          const SizedBox(height: 8),
          Text(
            '暂无帖子',
            style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildError(ThreadListController ctrl) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_outlined, size: 48, color: cs.outlineVariant),
            const SizedBox(height: 8),
            Text(
              '加载失败',
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              ctrl.errorMessage ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: ctrl.loadInitial,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
