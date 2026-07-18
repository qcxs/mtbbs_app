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
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (totalScore.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                totalScore,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.orange.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          // 表头
          _rateRow([
            _rateCell(Text('用户', style: _rateHeaderStyle)),
            ...columns.map(
              (c) => _rateCell(Text(c.toString(), style: _rateHeaderStyle)),
            ),
            if (hasReason) _rateCell(Text('理由', style: _rateHeaderStyle)),
          ]),
          const Divider(height: 1, color: Colors.orange),
          // 数据行
          ...entries.map((e) {
            final m = e as Map<String, dynamic>;
            final username = m['username'] as String? ?? '';
            final uid = m['uid'] as String? ?? '';
            final scores = m['scores'] as List<dynamic>? ?? [];
            final reason = m['reason'] as String? ?? '';
            return _rateRow([
              _rateCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    UserAvatar(uid: uid, nickname: username, radius: 10),
                    const SizedBox(width: 4),
                    Text(
                      username,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
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
                      color: Colors.orange.shade700,
                    ),
                  ),
                ),
              ),
              if (hasReason)
                _rateCell(
                  Text(
                    reason,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ]);
          }),
        ],
      ),
    );
  }

  TextStyle get _rateHeaderStyle => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: Colors.grey.shade600,
  );

  /// 单行横向排列
  Widget _rateRow(List<Widget> cells) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: cells
            .map(
              (c) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: c,
              ),
            )
            .toList(),
      ),
    );
  }

  /// 评分表格中的单元格
  Widget _rateCell(Widget child) {
    return child;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.white,
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
              style: TextStyle(color: Colors.grey.shade500),
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
                      color: Colors.deepPurple.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '回复',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.deepPurple.shade600,
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
                    _badge(widget.post.usergroup, Colors.orange),
                  ],
                  if (_isMainPost && widget.post.floorLabel.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    _badge(widget.post.floorLabel, Colors.deepPurple),
                  ],
                ],
              ),
              if (widget.post.postTime.isNotEmpty)
                Text(
                  widget.post.postTime,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              if (widget.post.ipLocation.isNotEmpty)
                Text(
                  widget.post.ipLocation,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
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
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                '#${widget.post.floor}',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
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
              color: _disableStyle ? Colors.red.shade600 : Colors.grey.shade600,
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
                color: Colors.grey.shade500,
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
          icon: Icon(Icons.more_horiz, size: 16, color: Colors.grey.shade500),
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

  Widget _badge(String text, MaterialColor color) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: color.shade50,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(
          text,
          style: TextStyle(fontSize: 10, color: color.shade700),
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final buttons = <Widget>[];

    if (widget.onRecommend != null) {
      buttons.add(
        _actionBtn(
          icon: widget.isLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
          color: widget.isLiked ? Colors.blue.shade500 : null,
          tooltip: '点赞',
          onTap: widget.onRecommend,
        ),
      );
    }

    if (widget.onFavorite != null) {
      buttons.add(
        _actionBtn(
          icon: widget.isFavorited ? Icons.bookmark : Icons.bookmark_border,
          color: widget.isFavorited ? Colors.amber.shade600 : null,
          tooltip: '收藏',
          onTap: widget.onFavorite,
        ),
      );
    }

    if (widget.onRate != null) {
      buttons.add(
        _actionBtn(
          icon: Icons.card_giftcard,
          tooltip: '评分',
          onTap: widget.onRate,
        ),
      );
    }

    if (widget.onKick != null) {
      buttons.add(
        _actionBtn(icon: Icons.report, tooltip: '踢帖', onTap: widget.onKick),
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
            child: Icon(icon, size: 18, color: color ?? Colors.grey.shade600),
          ),
        ),
      ),
    );
  }
}
