import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../models/thread_detail.dart';
import '../../widgets/thread_post_card.dart';

/// 主帖区组件
///
/// 未加载时显示占位符，点击后渲染完整主帖卡片。
class MainPostSection extends StatelessWidget {
  final PostItem post;
  final bool isLoaded;
  final bool isLiked;
  final bool isFavorited;
  final String tid;
  final VoidCallback? onTap;

  // 操作回调
  final VoidCallback? onRecommend;
  final VoidCallback? onFavorite;
  final VoidCallback? onRate;
  final VoidCallback? onKick;
  final void Function(PostCardAction action)? onPopupAction;

  const MainPostSection({
    super.key,
    required this.post,
    required this.isLoaded,
    required this.isLiked,
    required this.isFavorited,
    required this.tid,
    this.onTap,
    this.onRecommend,
    this.onFavorite,
    this.onRate,
    this.onKick,
    this.onPopupAction,
  });

  @override
  Widget build(BuildContext context) {
    if (!isLoaded) return _buildPlaceholder(context);
    return _buildPostCard(context);
  }

  Widget _buildPlaceholder(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.all(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(Icons.article_outlined, size: 40, color: cs.outlineVariant),
              const SizedBox(height: 8),
              Text(
                post.username.isNotEmpty ? '${post.username} 的帖子' : '主帖内容',
                style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Text(
                '点击加载帖子内容',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPostCard(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final settings = context.watch<SettingsProvider>();
    return ThreadPostCard(
      post: post,
      index: 0,
      tid: tid,
      isLiked: isLiked,
      isFavorited: isFavorited,
      isLoggedIn: auth.isLoggedIn,
      currentUid: auth.uid,
      globalDisabledTags: settings.disabledBbcodeTags,
      onRecommend: onRecommend,
      onFavorite: onFavorite,
      onRate: onRate,
      onKick: onKick,
      onPopupAction: onPopupAction,
    );
  }
}
