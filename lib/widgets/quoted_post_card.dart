import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/widgets/post_html_widget.dart';
import 'package:mtbbs/core/emoji_loader.dart';
import 'package:mtbbs/providers/settings_provider.dart';

/// 引用帖子卡片 — 用于回复评论时展示被引用的内容
///
/// 状态独立管理，不依赖外部 setState。
class QuotedPostCard extends StatefulWidget {
  final bool loading;
  final String? error;
  final Map<String, dynamic>? quotedPost;

  const QuotedPostCard({
    super.key,
    this.loading = false,
    this.error,
    this.quotedPost,
  });

  @override
  State<QuotedPostCard> createState() => _QuotedPostCardState();
}

class _QuotedPostCardState extends State<QuotedPostCard> {
  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return Container(
        padding: const EdgeInsets.all(12),
        color: Colors.amber.shade50,
        child: const Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('正在加载引用内容...', style: TextStyle(fontSize: 12)),
          ],
        ),
      );
    }

    if (widget.error != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        color: Colors.red.shade50,
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 14, color: Colors.red.shade400),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '加载失败: ${widget.error}',
                style: TextStyle(fontSize: 12, color: Colors.red.shade600),
              ),
            ),
          ],
        ),
      );
    }

    if (widget.quotedPost == null) return const SizedBox.shrink();

    final nickname = widget.quotedPost!['nickname']?.toString() ?? '';
    final bbcode = widget.quotedPost!['bbcode']?.toString() ?? '';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        border: Border(
          left: BorderSide(color: Colors.amber.shade300, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Icon(
                  Icons.format_quote,
                  size: 14,
                  color: Colors.orange.shade700,
                ),
                const SizedBox(width: 4),
                Text(
                  '回复 @$nickname',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade700,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _showDetailDialog(nickname, bbcode),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '查看',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (bbcode.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Text(
                bbcode.replaceAll(RegExp(r'\[/?[a-z0-9=,#]+\]'), ''),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ),
        ],
      ),
    );
  }

  void _showDetailDialog(String nickname, String bbcode) {
    final time = widget.quotedPost!['time']?.toString() ?? '';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 400),
        title: Row(
          children: [
            Expanded(
              child: Text(
                '@$nickname 的评论',
                style: const TextStyle(fontSize: 15),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.of(ctx).pop(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (time.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    time,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ),
              PostHtmlWidget(
                bbcode: bbcode,
                emojiMap: EmojiService().map,
                smilieIdMap: EmojiService().smilieIdMap,
                disabledTags: context
                    .read<SettingsProvider>()
                    .disabledBbcodeTags,
                autoDetectUrls: context
                    .read<SettingsProvider>()
                    .autoDetectUrls,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
