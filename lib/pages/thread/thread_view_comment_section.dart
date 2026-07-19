import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../models/thread_detail.dart';
import '../../widgets/thread_post_card.dart';

/// 评论区粘性头部委托
class CommentHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  CommentHeaderDelegate({required this.child});

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => child;

  @override
  double get minExtent => 44;

  @override
  double get maxExtent => 44;

  @override
  bool shouldRebuild(CommentHeaderDelegate oldDelegate) => true;
}

/// 评论区组件
///
/// 展示评论列表 + 分页头部（评论区标题 + 上下页按钮）。
/// 不管理任何状态，纯展示 + 回调。
class CommentSection extends StatelessWidget {
  final List<PostItem> posts;
  final Map<String, GlobalKey> postKeys;
  final int currentPage;
  final int totalPages;
  final bool pageLoading;
  final String tid;

  // 回调
  final void Function(int page)? onPrevPage;
  final void Function(int page)? onNextPage;
  final VoidCallback? onShowPagePicker;
  final void Function(ScrollNotification) onScrollNotification;
  final void Function(PostItem post)? onReply;
  final void Function(PostItem post)? onRecommend;
  final void Function(PostItem post)? onFavorite;
  final void Function(PostItem post)? onRate;
  final void Function(PostItem post)? onKick;
  final void Function(PostCardAction action, PostItem post)? onPopupAction;

  const CommentSection({
    super.key,
    required this.posts,
    required this.postKeys,
    required this.currentPage,
    required this.totalPages,
    required this.pageLoading,
    required this.tid,
    this.onPrevPage,
    this.onNextPage,
    this.onShowPagePicker,
    required this.onScrollNotification,
    this.onReply,
    this.onRecommend,
    this.onFavorite,
    this.onRate,
    this.onKick,
    this.onPopupAction,
  });

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty && pageLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (posts.isEmpty) return _buildEmpty();

    final auth = context.watch<AuthProvider>();
    final settings = context.watch<SettingsProvider>();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...posts.map(
          (post) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ThreadPostCard(
              key: postKeys.putIfAbsent(post.pid, () => GlobalKey()),
              post: post,
              index: currentPage,
              tid: tid,
              isLiked: false,
              isFavorited: false,
              isLoggedIn: auth.isLoggedIn,
              currentUid: auth.uid,
              globalDisabledTags: settings.disabledBbcodeTags,
              onReply: () => onReply?.call(post),
              onRecommend: () => onRecommend?.call(post),
              onFavorite: () => onFavorite?.call(post),
              onRate: () => onRate?.call(post),
              onKick: () => onKick?.call(post),
              onPopupAction: (action) => onPopupAction?.call(action, post),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text(
              '暂无评论',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  /// 评论区头部（标题 + 分页控件）
  static Widget buildHeader({
    required int currentPage,
    required int totalPages,
    required bool pageLoading,
    required VoidCallback? onPrev,
    required VoidCallback? onNext,
    required VoidCallback? onPageTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.white,
      child: Row(
        children: [
          Icon(Icons.forum_outlined, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Text(
            '评论区',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20),
            onPressed: onPrev,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
            tooltip: '上一页',
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onPageTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: pageLoading
                  ? SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.grey.shade500,
                      ),
                    )
                  : Text(
                      '$currentPage / $totalPages',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20),
            onPressed: onNext,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
            tooltip: '下一页',
          ),
        ],
      ),
    );
  }
}
