import 'package:flutter/material.dart';
import '../../models/thread_detail.dart';
import 'thread_post_card.dart';

/// 评论区列表（支持下拉刷新 + 触底加载）
///
/// [scrollable] 为 true（默认）时独立滚动，适用于宽屏布局；
/// 为 false 时嵌入父级滚轴，适用于窄屏布局。
class ThreadCommentList extends StatelessWidget {
  final List<PostItem> posts;
  final String tid;
  final bool isLoadingMore;
  final bool hasMore;
  final bool isLoggedIn;
  final String currentUid;
  final Future<void> Function() onRefresh;
  final void Function(ScrollNotification notification)? onScrollNotification;
  final VoidCallback? onLoadMore;

  /// 全局禁用的样式标签（从 SettingsProvider 传入）
  final Set<String>? globalDisabledTags;

  /// 是否独立滚动（含 RefreshIndicator），默认 true
  final bool scrollable;

  // 帖子操作回调
  final void Function(PostItem post)? onRecommend;
  final void Function(PostItem post)? onFavorite;
  final void Function(PostItem post)? onRate;
  final void Function(PostItem post)? onKick;
  final void Function(PostCardAction action, PostItem post)? onPopupAction;
  final void Function(PostItem post)? onReply;

  const ThreadCommentList({
    super.key,
    required this.posts,
    required this.tid,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.isLoggedIn = false,
    this.currentUid = '',
    required this.onRefresh,
    this.onScrollNotification,
    this.onLoadMore,
    this.globalDisabledTags,
    this.scrollable = true,
    this.onRecommend,
    this.onFavorite,
    this.onRate,
    this.onKick,
    this.onPopupAction,
    this.onReply,
  });

  List<Widget> _buildPostCards(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return [
      for (int i = 0; i < posts.length; i++) ...[
        if (i > 0) const Divider(height: 1),
        _buildPostCard(context, posts[i], i + 1),
      ],
      _buildFooter(cs),
    ];
  }

  Widget _buildPostCard(BuildContext context, PostItem post, int index) {
    return ThreadPostCard(
      post: post,
      index: index,
      tid: tid,
      isLoggedIn: isLoggedIn,
      currentUid: currentUid,
      globalDisabledTags: globalDisabledTags,
      onReply: () => onReply?.call(post),
      onRecommend: () => onRecommend?.call(post),
      onFavorite: () => onFavorite?.call(post),
      onRate: () => onRate?.call(post),
      onKick: () => onKick?.call(post),
      onPopupAction: (action) => onPopupAction?.call(action, post),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            '暂无回复',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    if (!scrollable) {
      // 嵌入模式：不独立滚动，不下拉刷新
      return NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (!scrollable) return false;
          if (notification is ScrollEndNotification) {
            final metrics = notification.metrics;
            if (metrics.maxScrollExtent > 0 &&
                metrics.pixels >= metrics.maxScrollExtent - 280) {
              onLoadMore?.call();
            }
          }
          return false;
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _buildPostCards(context),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification) {
          final metrics = notification.metrics;
          if (metrics.maxScrollExtent > 0 &&
              metrics.pixels >= metrics.maxScrollExtent - 280) {
            onLoadMore?.call();
          }
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView.separated(
          padding: const EdgeInsets.all(8),
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: posts.length + 1,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            if (i < posts.length) {
              return _buildPostCard(context, posts[i], i + 1);
            }
            return _buildFooter(Theme.of(context).colorScheme);
          },
        ),
      ),
    );
  }

  Widget _buildFooter(ColorScheme cs) {
    if (isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (!hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text(
            '没有更多了',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
