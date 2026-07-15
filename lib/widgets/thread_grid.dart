import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';
import '../controllers/thread_list_controller.dart';
import 'thread_card.dart';

/// 通用帖子列表网格
///
/// 功能：
/// - 下拉刷新（去重插顶部）
/// - 触底加载更多
/// - 响应式列数（手机 1 列，平板 2 列，桌面 3 列）
/// - 加载中骨架屏
/// - 空状态、错误状态显示
class ThreadGrid extends StatefulWidget {
  final ThreadListController controller;
  final bool visible;

  const ThreadGrid({
    super.key,
    required this.controller,
    this.visible = true,
  });

  @override
  State<ThreadGrid> createState() => _ThreadGridState();
}

class _ThreadGridState extends State<ThreadGrid>
    with AutomaticKeepAliveClientMixin {
  bool _everLoaded = false;

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
    // 页面从不可见变为可见时，触发加载
    if (!oldWidget.visible && widget.visible) {
      _checkLoad();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 首次可见时触发初始加载（initState 中不加载，延迟到这里）
    if (widget.visible) {
      _checkLoad();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onStateChanged);
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

  @override
  Widget build(BuildContext context) {
    super.build(context); // keep alive
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
      return RefreshIndicator(
        onRefresh: ctrl.refresh,
        child: LayoutBuilder(
          builder: (_, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: constraints.maxHeight > 0 ? constraints.maxHeight : null,
              child: _buildEmpty(),
            ),
          ),
        ),
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

        return RefreshIndicator(
          color: Theme.of(context).colorScheme.primary,
          onRefresh: ctrl.refresh,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollEndNotification) {
                final metrics = notification.metrics;
                if (metrics.maxScrollExtent > 0) {
                  const threshold = 280.0;
                  if (metrics.pixels >= metrics.maxScrollExtent - threshold) {
                    ctrl.loadMore();
                  }
                }
              }
              return false;
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (crossAxisCount == 1)
                  _buildListSliver(ctrl)
                else
                  _buildGridSliver(ctrl, crossAxisCount, spacing),
                _buildFooter(ctrl, crossAxisCount),
              ],
            ),
          ),
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
          );
        },
        childCount: ctrl.items.length,
      ),
    );
  }

  // ==================== 底部加载状态 ====================

  Widget _buildFooter(ThreadListController ctrl, int crossAxisCount) {
    // loadingMore 时显示骨架屏占位
    if (ctrl.state == LoadState.loadingMore) {
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildSkeletonCard(),
          childCount: 3,
        ),
      );
    }

    if (ctrl.state == LoadState.loading && ctrl.items.isNotEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    if (!ctrl.hasMore && ctrl.items.isNotEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Text(
              '已经全部加载',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
          ),
        ),
      );
    }

    return const SliverToBoxAdapter(child: SizedBox.shrink());
  }

  Widget _buildSkeletonCard() {
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
                  _skeletonBox(28, 28, 14),
                  const SizedBox(width: 6),
                  _skeletonBox(80, 12, 4),
                  const Spacer(),
                  _skeletonBox(50, 10, 4),
                ],
              ),
              const SizedBox(height: 10),
              _skeletonBox(double.infinity, 16, 4),
              const SizedBox(height: 4),
              _skeletonBox(double.infinity, 12, 4),
              const SizedBox(height: 8),
              _skeletonBox(double.infinity, 100, 6),
              const SizedBox(height: 8),
              Row(
                children: [
                  _skeletonBox(40, 12, 4),
                  const SizedBox(width: 12),
                  _skeletonBox(40, 12, 4),
                  const SizedBox(width: 12),
                  _skeletonBox(40, 12, 4),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== 骨架屏 ====================

  /// 骨架屏使用和真实数据相同的布局容器（LayoutBuilder → 响应式列数 → CustomScrollView），
  /// 确保骨架屏→真实卡片的过渡无缝，列数变化时骨架屏也同步适配。
  Widget _buildSkeleton() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = _crossAxisCount(constraints.maxWidth);
        final spacing = _gridSpacing(constraints.maxWidth);

        return RefreshIndicator(
          color: Theme.of(context).colorScheme.primary,
          onRefresh: widget.controller.refresh,
          child: CustomScrollView(
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
                      child: _buildSkeletonCard(),
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
                    itemBuilder: (context, index) => _buildSkeletonCard(),
                    childCount: 8,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _skeletonBox(double w, double h, double r) {
    return Container(
      width: w == double.infinity ? null : w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(r),
      ),
    );
  }

  // ==================== 空状态 / 错误状态 ====================

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Text(
            '暂无帖子',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildError(ThreadListController ctrl) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi_off_outlined,
              size: 48,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 8),
            Text(
              '加载失败',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 4),
            Text(
              ctrl.errorMessage ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
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
