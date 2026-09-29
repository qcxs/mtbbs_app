part of 'thread_grid.dart';

/// [ThreadGrid] 的构建逻辑。
///
/// `build` 是接口成员不能整体搬走：宿主保留 `build` 薄覆写（并调用
/// `super.build` 以满足 `AutomaticKeepAliveClientMixin` 的 keep-alive 注册），
/// 原体改名 `_buildPage` 承载于此。
extension on _ThreadGridState {
  Widget _buildPage(BuildContext context) {
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
                  child: _buildEmpty(),
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
            key: ValueKey('thread_${item.threadId}'),
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

  Widget _buildEmpty() {
    return const EmptyView(icon: Icons.inbox_outlined, text: '暂无帖子');
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
