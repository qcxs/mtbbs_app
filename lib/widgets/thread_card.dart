import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../models/thread_item.dart';
import '../models/thread_detail.dart';
import 'user_avatar.dart';
import 'image_preview/image_preview.dart';
import 'post_html_widget.dart';

/// 帖子卡片 Widget
///
/// 布局（从上到下）：
///   用户行 | 标题 | 摘要 | 图片(固定高度/裁剪) | 底部栏(版块+统计)
///   查看回复(可选) | 展开的回复列表(可选)
/// 图片区总是固定高度 + BoxFit.cover 裁剪，卡片高度可预期。
class ThreadCard extends StatelessWidget {
  final ThreadItem item;
  final VoidCallback? onTap;
  final VoidCallback? onViewReplies;
  final List<PostItem>? replies;
  final bool repliesLoading;
  final String? replyError;

  const ThreadCard({
    super.key,
    required this.item,
    this.onTap,
    this.onViewReplies,
    this.replies,
    this.repliesLoading = false,
    this.replyError,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildUserRow(context),
              const SizedBox(height: 6),
              _buildTitle(),
              if (item.summary != null && item.summary!.isNotEmpty) ...[
                const SizedBox(height: 4),
                _buildSummary(context),
              ],
              if (item.images != null && item.images!.isNotEmpty) ...[
                const SizedBox(height: 6),
                _buildImages(context),
              ],
              const SizedBox(height: 6),
              _buildBottomBar(context),
              if (onViewReplies != null) ...[
                const SizedBox(height: 6),
                if (repliesLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (replyError != null) ...[
                  Container(
                    decoration: BoxDecoration(
                      color: cs.errorContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, size: 14, color: cs.error),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            replyError!,
                            style: TextStyle(fontSize: 11, color: cs.error),
                          ),
                        ),
                        GestureDetector(
                          onTap: onViewReplies,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '收起',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (replies != null && replies!.isNotEmpty) ...[
                  Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 顶部：标题 + 收起按钮
                        Row(
                          children: [
                            Text(
                              '回复 (${replies!.length})',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: onViewReplies,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '收起',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        for (final reply in replies!)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                UserAvatar(
                                  uid: reply.uid,
                                  nickname: reply.username,
                                  radius: 12,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        reply.username,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                      PostHtmlWidget(
                                        bbcode: reply.bbcode,
                                        fontSize: 11,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ] else ...[
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: onViewReplies,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '查看回复',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ==================== 用户信息行 ====================

  Widget _buildUserRow(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasTime = item.time != null && item.time!.isNotEmpty;
    return Row(
      children: [
        UserAvatar(
          uid: '${item.uid ?? ''}',
          nickname: item.nickname,
          radius: 18,
        ),
        const SizedBox(width: 8),
        // 左侧：昵称 + 等级标签
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: GestureDetector(
                  onTap: () => context.push('/user/${item.uid ?? ''}'),
                  child: Text(
                    item.nickname ?? '匿名',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (item.level != null && item.level!.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9900).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    item.level!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFFF9900),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (hasTime) ...[
          const SizedBox(width: 8),
          Text(
            item.time!,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  // ==================== 标题 ====================

  Widget _buildTitle() {
    return Text(
      item.title ?? '',
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  // ==================== 摘要 ====================

  Widget _buildSummary(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      item.summary!,
      style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant, height: 1.4),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  // ==================== 图片区（固定高度 + 自动裁剪）====================

  Widget _buildImages(BuildContext context) {
    final images = item.images!;
    final onTapImage = onTap; // 点击图片 = 进入帖子
    if (images.length == 1) {
      return GestureDetector(
        onTap: () => onTapImage?.call(),
        onLongPress: () => showImageActions(
          context,
          imageUrls: images,
          initialIndex: 0,
          sourceInfo: '帖子图片',
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: CachedNetworkImage(
            imageUrl: images.first,
            width: double.infinity,
            height: 140,
            memCacheWidth: 280,
            memCacheHeight: 280,
            fit: BoxFit.cover,
            placeholder: (_, __) => _buildPlaceholder(140, context),
            errorWidget: (_, __, ___) => _buildPlaceholder(140, context),
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: () => onTapImage?.call(),
      onLongPress: () => showImageActions(
        context,
        imageUrls: images,
        initialIndex: 0,
        sourceInfo: '帖子图片',
      ),
      child: SizedBox(
        height: 90,
        child: Row(
          children: images
              .take(3)
              .map(
                (url) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CachedNetworkImage(
                        imageUrl: url,
                        width: double.infinity,
                        height: 90,
                        memCacheWidth: 180,
                        memCacheHeight: 180,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _buildPlaceholder(90, context),
                        errorWidget: (_, __, ___) =>
                            _buildPlaceholder(90, context),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(double height, BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: height,
      color: cs.surfaceContainerLow,
      child: Center(
        child: Icon(Icons.image_outlined, color: cs.outlineVariant, size: 28),
      ),
    );
  }

  // ==================== 底部：左板块 + 右统计 ====================

  Widget _buildBottomBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        // 板块标签 — 可点击，过长时截断
        if (item.boardName != null && item.boardName!.isNotEmpty)
          Flexible(
            child: GestureDetector(
              onTap: () {
                final fid = item.boardId;
                if (fid != null) {
                  context.push('/forum?fid=$fid');
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF53BCF5).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  item.boardName!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF53BCF5),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        const Spacer(),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _statItem(Icons.favorite_border, item.likes, cs),
            const SizedBox(width: 10),
            _statItem(Icons.chat_bubble_outline, item.comments, cs),
            const SizedBox(width: 10),
            _statItem(Icons.visibility_outlined, item.views, cs),
          ],
        ),
      ],
    );
  }

  Widget _statItem(IconData icon, int? count, ColorScheme cs) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: cs.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(
          _formatCount(count ?? 0),
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  String _formatCount(int count) {
    if (count >= 10000) return '${(count / 10000).toStringAsFixed(1)}w';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return count.toString();
  }
}
