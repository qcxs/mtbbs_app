import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mtbbs/api/home/follow/export.dart' as follow_api;
import 'package:mtbbs/api/home/follow/parse.dart' show parseFollowHref;
import 'package:mtbbs/config/brand_colors.dart';
import 'package:mtbbs/core/app/app_capabilities.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/models/thread_detail.dart';
import 'package:mtbbs/core/app/site_scope.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/utils/clipboard_helper.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/bbcode/post_html_widget.dart';
import 'package:mtbbs/widgets/common/app_sheet.dart';
import 'package:mtbbs/widgets/common/user_avatar.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';
import 'package:mtbbs/widgets/dialog/confirm_dialog.dart';

/// 帖子卡片操作类型（PopupMenu）
enum PostCardAction { showBbcode, editPost, viewTime, rate, saveImage }

/// 帖子/评论卡片组件
///
/// 接收 BBCode 字符串和所有必要的回调，不持有任何业务状态。
class ThreadPostCard extends StatefulWidget {
  final PostItem post;
  final int index;
  final String tid;
  final bool isLiked;
  final bool isLoggedIn;
  final String currentUid;

  /// 楼主（主题作者）uid；评论作者与之相同时显示"楼主"标志
  final String opUid;

  /// 全局禁用的样式标签（从 SettingsProvider 传入）
  final Set<String>? globalDisabledTags;

  /// 页面级"全局禁用样式"开关（顶栏 toggle），开启时禁用所有样式
  final bool globalDisableStyle;

  /// 只读模式（离线/缓存快照页）：隐藏回复、评分、编辑等互动入口
  final bool readOnly;

  final VoidCallback? onReply;
  final VoidCallback? onRecommend;
  final void Function(PostCardAction action)? onPopupAction;

  const ThreadPostCard({
    super.key,
    required this.post,
    required this.index,
    required this.tid,
    this.isLiked = false,
    this.isLoggedIn = false,
    this.currentUid = '',
    this.opUid = '',
    this.globalDisabledTags,
    this.globalDisableStyle = false,
    this.readOnly = false,
    this.onReply,
    this.onRecommend,
    this.onPopupAction,
  });

  @override
  State<ThreadPostCard> createState() => _ThreadPostCardState();
}

class _ThreadPostCardState extends State<ThreadPostCard> {
  /// 单帖临时禁用所有样式
  bool _disableStyle = false;

  /// 关注状态本地覆盖（服务端 followUrl 为准，操作成功后立即切换）
  bool? _followedOverride;

  /// 关注请求进行中
  bool _followBusy = false;

  @override
  void didUpdateWidget(covariant ThreadPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换帖（翻页/刷新）后以新服务端数据为准
    if (oldWidget.post.pid != widget.post.pid ||
        oldWidget.post.followUrl != widget.post.followUrl) {
      _followedOverride = null;
      _followBusy = false;
    }
  }

  /// 合并全局设置 + 单帖开关 + 页面级全局开关的禁用标签
  Set<String> get _effectiveDisabledTags {
    if (!_disableStyle && !widget.globalDisableStyle) {
      return widget.globalDisabledTags ?? const {};
    }
    final combined = Set<String>.from(widget.globalDisabledTags ?? const {});
    combined.addAll(bbcodeStyleTags);
    return combined;
  }

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
    // 最多显示的评分条数（设置项，0 = 全部显示）；其余收进「查看全部」
    final maxRows = context.select<SettingsProvider, int>(
      (s) => s.ratingMaxRows,
    );
    final preview = maxRows > 0 && entries.length > maxRows
        ? entries.sublist(0, maxRows)
        : entries;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题行：图标 + 「评分」 + 汇总（克米是金额汇总，52pojie 是参与人数）
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: Row(
              children: [
                Icon(Icons.star_rounded, size: 14, color: cs.primary),
                const SizedBox(width: 4),
                const Text(
                  '评分',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                if (totalScore.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      totalScore,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (entries.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _RatingTable(
                columns: columns,
                entries: preview,
                hasReason: hasReason,
              ),
            ),
          if (entries.length > preview.length)
            _ratingViewAllButton(context, entries.length),
        ],
      ),
    );
  }

  /// 本楼「点评」（楼中楼）：作者 + 内容 + 时间
  Widget _buildComments(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final comments = widget.post.comments;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: Row(
              children: [
                Icon(Icons.chat_bubble_outline, size: 14, color: cs.primary),
                const SizedBox(width: 4),
                const Text(
                  '点评',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
                Text(
                  '${comments.length}',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          for (final c in comments)
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: cs.outlineVariant, width: 0.5),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  UserAvatar(uid: c.uid, nickname: c.username, radius: 12),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                c.username,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (c.time.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text(
                                c.time,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (c.message.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              c.message,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 「查看全部 N 条评分」入口
  Widget _ratingViewAllButton(BuildContext context, int total) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showAllRatings(context),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: cs.outlineVariant, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.format_list_bulleted, size: 14, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                '查看全部 $total 条评分',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: cs.primary,
                ),
              ),
              const Spacer(),
              Icon(Icons.chevron_right, size: 16, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }

  /// 弹层展示完整评分列表（可上下滚动，列超宽时横向滚动）
  void _showAllRatings(BuildContext context) {
    final rating = widget.post.rating;
    if (rating == null) return;
    final totalScore = rating['totalScore'] as String? ?? '';
    final columns = rating['columns'] as List<dynamic>? ?? [];
    final entries = rating['entries'] as List<dynamic>? ?? [];
    if (entries.isEmpty) return;
    final hasReason = entries.any(
      (e) => (e['reason'] as String? ?? '').isNotEmpty,
    );

    showAppSheet(
      context: context,
      maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AppSheetScaffold(
          title: '评分记录（${entries.length} 人）',
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (totalScore.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      totalScore,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _RatingTable(
                    columns: columns,
                    entries: entries,
                    hasReason: hasReason,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 楼层解析失败：显示降级提示，别让用户把"空白楼层"当成帖子本来就是空的
    if (widget.post.degraded) {
      return Container(
        padding: const EdgeInsets.all(12),
        color: cs.surface,
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '该楼层（${widget.post.floorText}）解析失败，可能页面结构已变更',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }
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
          if (widget.post.comments.isNotEmpty) _buildComments(context),
          if (widget.post.rating != null) _buildRating(context),
          if (!widget.readOnly && !widget.post.isOp)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 评分（文字入口，显示在底部而非"更多"菜单）
                    _textAction(
                      cs,
                      '评分',
                      () => widget.onPopupAction?.call(PostCardAction.rate),
                    ),
                    const SizedBox(width: 8),
                    _textAction(cs, '回复', widget.onReply),
                  ],
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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 昵称 + 标签：用 Wrap 允许换行，避免标签多（楼主/置顶回复…）时横向溢出
                  Expanded(
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          widget.post.username,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        if (widget.post.usergroup.isNotEmpty)
                          _badge(
                            widget.post.usergroup,
                            levelColor,
                            levelColor.withValues(alpha: 0.12),
                          ),
                        // 楼主标志：主帖本身（isOp）或评论作者与楼主 uid 相同
                        if (widget.post.isOp ||
                            (widget.post.uid.isNotEmpty &&
                                widget.post.uid == widget.opUid))
                          _badge('楼主', cs.onPrimary, cs.primary),
                        // 置顶回复（管理员置顶的评论）
                        if (widget.post.isStickReply)
                          _badge(
                            '置顶回复',
                            stickTopColor,
                            stickTopColor.withValues(alpha: 0.12),
                          ),
                        // 楼主关注入口（仅主帖、非本人、可写场景）
                        if (_showFollowChip) _buildFollowChip(context),
                      ],
                    ),
                  ),
                  // 主题印章（如「精华」）：右侧盖章式渲染，比普通标签更突出
                  if (widget.post.stamp.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    digestColor.toStamp(widget.post.stamp, fontSize: 13),
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
            onTap: () async {
              final url =
                  '${SiteStore.instance.baseUrl}/forum.php?mod=redirect&goto=findpost&ptid=${widget.tid}&pid=${widget.post.pid}';
              final ok = await ClipboardHelper.write(url);
              showToast(
                ok
                    ? '复制楼层成功：tid：${widget.tid}，pid：${widget.post.pid}'
                    : '复制到剪切板失败',
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                widget.post.floorText,
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
        if (!widget.readOnly &&
            widget.post.pid.isNotEmpty &&
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
        // 更多操作（只读模式隐藏）
        if (!widget.readOnly)
          PopupMenuButton<PostCardAction>(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: Icon(Icons.more_horiz, size: 16, color: cs.onSurfaceVariant),
            onSelected: (action) => widget.onPopupAction?.call(action),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: PostCardAction.showBbcode,
                child: Text('借鉴一下', style: TextStyle(fontSize: 13)),
              ),
              if (widget.post.postTime.length < 15)
                PopupMenuItem(
                  value: PostCardAction.viewTime,
                  enabled: widget.post.pid.isNotEmpty,
                  child: const Text('查看时间', style: TextStyle(fontSize: 13)),
                ),
              if (AppCapabilities.isAvailable(AppCapability.saveImage))
                const PopupMenuItem(
                  value: PostCardAction.saveImage,
                  child: Text('生成图片', style: TextStyle(fontSize: 13)),
                ),
            ],
          ),
      ],
    );
  }

  /// 是否展示楼主关注入口：仅主帖、已登录、非本人、非只读（离线/跨站点临时会话）
  bool get _showFollowChip =>
      widget.post.isOp &&
      !widget.readOnly &&
      widget.isLoggedIn &&
      widget.post.uid.isNotEmpty &&
      widget.post.uid != widget.currentUid &&
      widget.post.followUrl.isNotEmpty;

  bool get _followedNow =>
      _followedOverride ?? parseFollowHref(widget.post.followUrl).followed;

  /// 作者关注小胶囊：「关注」/「已关注」，操作成功后本地即时切换
  Widget _buildFollowChip(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final followed = _followedNow;
    final fg = followed ? cs.onSurfaceVariant : cs.primary;
    return GestureDetector(
      onTap: _followBusy ? null : _toggleFollowAuthor,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: followed
              ? cs.surfaceContainerHigh
              : cs.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: followed
                ? cs.outlineVariant.withValues(alpha: 0.6)
                : cs.primary.withValues(alpha: 0.35),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(followed ? Icons.check : Icons.add, size: 10, color: fg),
            const SizedBox(width: 2),
            Text(
              _followBusy ? '处理中' : (followed ? '已关注' : '关注'),
              style: TextStyle(fontSize: 10, color: fg),
            ),
          ],
        ),
      ),
    );
  }

  /// 关注 / 取消关注楼主（取消需二次确认）
  Future<void> _toggleFollowAuthor() async {
    if (_followBusy) return;
    if (!widget.isLoggedIn) {
      showToast('请先登录');
      return;
    }
    final followed = _followedNow;
    if (followed) {
      final ok = await showConfirmDialog(
        context,
        title: '取消关注',
        message: '确定不再关注 ${widget.post.username} 吗？',
        confirmText: '取消关注',
        danger: true,
      );
      if (ok != true) return;
      if (!mounted) return;
    }

    setState(() => _followBusy = true);
    final dio = SiteScope.read(context).dio;
    try {
      final result = followed
          ? await follow_api.unfollowUser(dio, uid: widget.post.uid)
          : await follow_api.followUser(
              dio,
              uid: widget.post.uid,
              formhash: parseFollowHref(widget.post.followUrl).formhash,
            );
      if (!mounted) return;
      final success = result['success'] == true;
      setState(() {
        _followBusy = false;
        if (success) _followedOverride = !followed;
      });
      showToast(
        success
            ? (followed ? '已取消关注' : '已关注')
            : (result['message']?.toString() ?? '操作失败'),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _followBusy = false);
      showToast('操作失败：$e');
    }
  }

  Widget _badge(String text, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: textColor)),
    );
  }

  /// 底部文字操作按钮（评分/回复等）
  ///
  /// 点赞/评分等对帖子的操作统一放到页面底部回复栏（收藏旁），
  /// 卡片底部只保留"评分"与"回复"两个文字入口。
  Widget _textAction(ColorScheme cs, String label, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// 评分表格：帖内传截断后的 [entries]，弹层传全量。
class _RatingTable extends StatelessWidget {
  const _RatingTable({
    required this.columns,
    required this.entries,
    required this.hasReason,
  });

  final List<dynamic> columns;
  final List<dynamic> entries;
  final bool hasReason;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Table(
        border: TableBorder(
          top: BorderSide(color: cs.outlineVariant, width: 0.5),
          bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
          horizontalInside: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
        defaultColumnWidth: const IntrinsicColumnWidth(),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          // 表头行
          TableRow(
            decoration: BoxDecoration(color: cs.surfaceContainerHigh),
            children: [
              _cell(Text('用户', style: _headerStyle(cs))),
              ...columns.map(
                (c) => _cell(Text(c.toString(), style: _headerStyle(cs))),
              ),
              if (hasReason) _cell(Text('理由', style: _headerStyle(cs))),
            ],
          ),
          // 数据行（斑马纹便于横向阅读）
          ...entries.asMap().entries.map((pair) {
            final index = pair.key;
            final m = pair.value as Map<String, dynamic>;
            final username = m['username'] as String? ?? '';
            final uid = m['uid'] as String? ?? '';
            final scores = m['scores'] as List<dynamic>? ?? [];
            final reason = m['reason'] as String? ?? '';
            return TableRow(
              decoration: BoxDecoration(
                color: index.isOdd ? cs.surfaceContainer : null,
              ),
              children: [
                _cell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      UserAvatar(uid: uid, nickname: username, radius: 10),
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
                  (s) => _cell(
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
                  _cell(
                    ConstrainedBox(
                      // 理由列限宽后自动换行：不截断、不加省略号
                      // （默认只展示前 10 行，行高增长可接受）
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text(
                        reason,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }

  TextStyle _headerStyle(ColorScheme cs) => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: cs.onSurfaceVariant,
  );

  /// 评分表格单元格
  Widget _cell(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: child,
    );
  }
}
