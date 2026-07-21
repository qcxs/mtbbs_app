import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/thread_detail.dart';
import '../../config/site_config.dart';
import '../../core/emoji_loader.dart';
import '../../providers/settings_provider.dart';
import 'post_html_widget.dart';
import 'user_avatar.dart';

/// 帖子卡片操作类型（PopupMenu）
enum PostCardAction { showBbcode, editPost, viewTime }

/// 帖子/评论卡片组件
///
/// 接收 BBCode 字符串和所有必要的回调，不持有任何业务状态。
class ThreadPostCard extends StatefulWidget {
  final PostItem post;
  final int index;
  final String tid;
  final bool isLiked;
  final bool isFavorited;
  final bool isLoggedIn;
  final String currentUid;

  /// 全局禁用的样式标签（从 SettingsProvider 传入）
  final Set<String>? globalDisabledTags;

  final VoidCallback? onReply;
  final VoidCallback? onRecommend;
  final VoidCallback? onFavorite;
  final VoidCallback? onRate;
  final VoidCallback? onKick;
  final void Function(PostCardAction action)? onPopupAction;

  const ThreadPostCard({
    super.key,
    required this.post,
    required this.index,
    required this.tid,
    this.isLiked = false,
    this.isFavorited = false,
    this.isLoggedIn = false,
    this.currentUid = '',
    this.globalDisabledTags,
    this.onReply,
    this.onRecommend,
    this.onFavorite,
    this.onRate,
    this.onKick,
    this.onPopupAction,
  });

  @override
  State<ThreadPostCard> createState() => _ThreadPostCardState();
}

class _ThreadPostCardState extends State<ThreadPostCard> {
  /// 单帖临时禁用所有样式
  bool _disableStyle = false;

  /// 合并全局 + 局部的禁用标签
  Set<String> get _effectiveDisabledTags {
    if (!_disableStyle) return widget.globalDisabledTags ?? const {};
    final combined = Set<String>.from(widget.globalDisabledTags ?? const {});
    combined.addAll(bbcodeStyleTags);
    return combined;
  }

  bool get _isMainPost => widget.index == 0;

  Widget _buildRating(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rating = widget.post.rating!;
    final totalScore = rating['totalScore'] as String? ?? '';
    final columns = rating['columns'] as List<dynamic>? ?? [];
    final entries = rating['entries'] as List<dynamic>? ?? [];

    if (columns.isEmpty && entries.isEmpty) return const SizedBox.shrink();
    final hasReason = entries.any(
      (e) => (e['reason'] as String? ?? '').isNotEmpty,
    );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (totalScore.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                totalScore,
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              border: TableBorder.all(color: cs.outline, width: 0.5),
              defaultColumnWidth: const IntrinsicColumnWidth(),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                // 表头行
                TableRow(
                  decoration: BoxDecoration(color: cs.surfaceContainerHigh),
                  children: [
                    _rateCell(Text('用户', style: _rateHeaderStyle(cs))),
                    ...columns.map(
                      (c) => _rateCell(
                        Text(c.toString(), style: _rateHeaderStyle(cs)),
                      ),
                    ),
                    if (hasReason)
                      _rateCell(Text('理由', style: _rateHeaderStyle(cs))),
                  ],
                ),
                // 数据行
                ...entries.map((e) {
                  final m = e as Map<String, dynamic>;
                  final username = m['username'] as String? ?? '';
                  final uid = m['uid'] as String? ?? '';
                  final scores = m['scores'] as List<dynamic>? ?? [];
                  final reason = m['reason'] as String? ?? '';
                  return TableRow(
                    children: [
                      _rateCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            UserAvatar(
                              uid: uid,
                              nickname: username,
                              radius: 10,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              username,
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...scores.map(
                        (s) => _rateCell(
                          Text(
                            s.toString(),
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      if (hasReason)
                        _rateCell(
                          Text(
                            reason,
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _rateHeaderStyle(ColorScheme cs) => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: cs.onSurfaceVariant,
  );

  /// 评分表格单元格
  Widget _rateCell(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      color: cs.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: 8),
          if (widget.post.bbcode.isNotEmpty)
            PostHtmlWidget(
              bbcode: widget.post.bbcode,
              emojiMap: EmojiService().map,
              smilieIdMap: EmojiService().smilieIdMap,
              disabledTags: _effectiveDisabledTags,
              autoDetectUrls: widget.globalDisabledTags != null
                  ? context.read<SettingsProvider>().autoDetectUrls
                  : true,
            )
          else
            Text(
              widget.post.bbcode,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          if (widget.post.rating != null) _buildRating(context),
          if (_isMainPost) _buildActionButtons(context),
          if (!widget.post.isOp)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: widget.onReply,
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
                      '回复',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        UserAvatar(
          uid: widget.post.uid,
          nickname: widget.post.username,
          radius: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    widget.post.username,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  if (widget.post.usergroup.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    _badge(
                      widget.post.usergroup,
                      const Color(0xFFFF9900),
                      const Color(0xFFFF9900).withOpacity(0.12),
                    ),
                  ],
                  if (_isMainPost && widget.post.floorLabel.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    _badge(
                      widget.post.floorLabel,
                      cs.onSurfaceVariant,
                      cs.surfaceContainerLow,
                    ),
                  ],
                ],
              ),
              if (widget.post.postTime.isNotEmpty)
                Text(
                  widget.post.postTime,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              if (widget.post.ipLocation.isNotEmpty)
                Text(
                  widget.post.ipLocation,
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
            ],
          ),
        ),
        if (!widget.post.isOp && widget.post.floor > 0)
          GestureDetector(
            onTap: () {
              final url =
                  '${SiteConfig.baseUrl}/forum.php?mod=redirect&goto=findpost&ptid=${widget.tid}&pid=${widget.post.pid}';
              Clipboard.setData(ClipboardData(text: url));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '复制楼层成功：tid：${widget.tid}，pid：${widget.post.pid}',
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                '#${widget.post.floor}',
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              ),
            ),
          ),
        // 单帖样式禁用 toggle
        IconButton(
          icon: Text(
            _disableStyle ? 'T̶' : 'T',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _disableStyle ? cs.error : cs.onSurfaceVariant,
            ),
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          tooltip: _disableStyle ? '恢复样式渲染' : '禁用样式渲染',
          onPressed: () => setState(() => _disableStyle = !_disableStyle),
        ),
        const SizedBox(width: 2),
        // 编辑按钮（仅自己可见）
        if (widget.post.pid.isNotEmpty &&
            widget.post.uid == widget.currentUid &&
            widget.post.uid.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: IconButton(
              icon: Icon(
                Icons.edit_outlined,
                size: 16,
                color: cs.onSurfaceVariant,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: '编辑',
              onPressed: () =>
                  widget.onPopupAction?.call(PostCardAction.editPost),
            ),
          ),
        // 更多操作
        PopupMenuButton<PostCardAction>(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          icon: Icon(Icons.more_horiz, size: 16, color: cs.onSurfaceVariant),
          onSelected: (action) {
            if (action == PostCardAction.showBbcode ||
                action == PostCardAction.editPost ||
                action == PostCardAction.viewTime) {
              widget.onPopupAction?.call(action);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: PostCardAction.showBbcode,
              child: Text('查看 BBCode', style: TextStyle(fontSize: 13)),
            ),
            if (widget.post.postTime.length < 15)
              PopupMenuItem(
                value: PostCardAction.viewTime,
                enabled: widget.post.pid.isNotEmpty,
                child: const Text('查看时间', style: TextStyle(fontSize: 13)),
              ),
          ],
        ),
      ],
    );
  }

  Widget _badge(String text, Color textColor, Color bgColor) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(text, style: TextStyle(fontSize: 10, color: textColor)),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final buttons = <Widget>[];

    if (widget.onRecommend != null) {
      buttons.add(
        _actionBtn(
          icon: widget.isLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
          color: widget.isLiked ? cs.onSurfaceVariant : null,
          tooltip: '点赞',
          onTap: widget.onRecommend,
          cs: cs,
        ),
      );
    }

    if (widget.onFavorite != null) {
      buttons.add(
        _actionBtn(
          icon: widget.isFavorited ? Icons.bookmark : Icons.bookmark_border,
          color: widget.isFavorited ? cs.onSurfaceVariant : null,
          tooltip: '收藏',
          onTap: widget.onFavorite,
          cs: cs,
        ),
      );
    }

    if (widget.onRate != null) {
      buttons.add(
        _actionBtn(
          icon: Icons.card_giftcard,
          tooltip: '评分',
          onTap: widget.onRate,
          cs: cs,
        ),
      );
    }

    if (widget.onKick != null) {
      buttons.add(
        _actionBtn(
          icon: Icons.report,
          tooltip: '踢帖',
          onTap: widget.onKick,
          cs: cs,
        ),
      );
    }

    if (buttons.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(mainAxisSize: MainAxisSize.min, children: buttons),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    Color? color,
    required String tooltip,
    required VoidCallback? onTap,
    required ColorScheme cs,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 18, color: color ?? cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
