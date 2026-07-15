import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../models/thread_item.dart';
import 'user_avatar.dart';
import 'image_preview/image_preview.dart';

/// 帖子卡片 Widget
///
/// 布局（从上到下）：
///   用户行 | 标题 | 摘要 | 图片(固定高度/裁剪) | 底部栏(版块+统计)
/// 图片区总是固定高度 + BoxFit.cover 裁剪，卡片高度可预期。
class ThreadCard extends StatelessWidget {
  final ThreadItem item;
  final VoidCallback? onTap;

  const ThreadCard({super.key, required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
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
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildUserRow(context),
              const SizedBox(height: 6),
              _buildTitle(),
              if (item.summary != null && item.summary!.isNotEmpty) ...[
                const SizedBox(height: 4),
                _buildSummary(),
              ],
              if (item.images != null && item.images!.isNotEmpty) ...[
                const SizedBox(height: 6),
                _buildImages(context),
              ],
              const SizedBox(height: 6),
              _buildBottomBar(context),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== 用户信息行 ====================

  Widget _buildUserRow(BuildContext context) {
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
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    item.level!,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange.shade700,
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
            style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
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

  Widget _buildSummary() {
    return Text(
      item.summary!,
      style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.4),
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
            placeholder: (_, __) => _buildPlaceholder(140),
            errorWidget: (_, __, ___) => _buildPlaceholder(140),
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
                        placeholder: (_, __) => _buildPlaceholder(90),
                        errorWidget: (_, __, ___) => _buildPlaceholder(90),
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

  Widget _buildPlaceholder(double height) {
    return Container(
      height: height,
      color: Colors.grey.shade100,
      child: Center(
        child: Icon(
          Icons.image_outlined,
          color: Colors.grey.shade300,
          size: 28,
        ),
      ),
    );
  }

  // ==================== 底部：左板块 + 右统计 ====================

  Widget _buildBottomBar(BuildContext context) {
    return Row(
      children: [
        // 板块标签 — 可点击，过长时截断
        if (item.boardName != null && item.boardName!.isNotEmpty)
          Flexible(
            child: GestureDetector(
              onTap: () => _toast(context, '查看板块: ${item.boardName}'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  item.boardName!,
                  style: TextStyle(fontSize: 11, color: Colors.blue.shade600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        const Spacer(),
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _statItem(Icons.favorite_border, item.likes),
              const SizedBox(width: 10),
              _statItem(Icons.chat_bubble_outline, item.comments),
              const SizedBox(width: 10),
              _statItem(Icons.visibility_outlined, item.views),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statItem(IconData icon, int? count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade400),
        const SizedBox(width: 3),
        Text(
          _formatCount(count ?? 0),
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
      ],
    );
  }

  String _formatCount(int count) {
    if (count >= 10000) return '${(count / 10000).toStringAsFixed(1)}w';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return count.toString();
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 1)),
    );
  }
}
