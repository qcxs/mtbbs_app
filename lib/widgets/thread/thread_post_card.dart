import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mtbbs/config/brand_colors.dart';
import 'package:mtbbs/core/app/app_capabilities.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/models/thread_detail.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/bbcode/post_html_widget.dart';
import 'package:mtbbs/widgets/common/app_sheet.dart';
import 'package:mtbbs/widgets/common/user_avatar.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';

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

  /// 合并全局设置 + 单帖开关 + 页面级全局开关的禁用标签
  Set<String> get _effectiveDisabledTags {
    if (!_disableStyle && !widget.globalDisableStyle) {
      return widget.globalDisabledTags ?? const {};
    }
    final combined = Set<String>.from(widget.globalDisabledTags ?? const {});
    combined.addAll(bbcodeStyleTags);
    return combined;
  }

  /// 帖内最多展示的评分条数：52pojie 的评分列表常有一二十条，
  /// 全量铺开会把楼层撑得很长，其余统一收进「查看全部」弹层
  static const int _ratingPreviewRows = 10;

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
    final preview = entries.length > _ratingPreviewRows
        ? entries.sublist(0, _ratingPreviewRows)
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
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (entries.isNotEmpty)
            ConstrainedBox(
              // 兜底：10 条约 300px，即使系统字号放大也不会撑破楼层
              constraints: const BoxConstraints(maxHeight: 340),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _RatingTable(
                  columns: columns,
                  entries: preview,
                  hasReason: hasReason,
                ),
              ),
            ),
          if (entries.length > preview.length)
            _ratingViewAllButton(context, entries.length),
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
                    wrapReason: true,
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
            onTap: () {
              final url =
                  '${SiteStore.instance.baseUrl}/forum.php?mod=redirect&goto=findpost&ptid=${widget.tid}&pid=${widget.post.pid}';
              Clipboard.setData(ClipboardData(text: url));
              showToast('复制楼层成功：tid：${widget.tid}，pid：${widget.post.pid}');
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
                child: Text('查看 BBCode', style: TextStyle(fontSize: 13)),
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

/// 评分表格：帖内传截断后的 [entries]，弹层传全量并允许理由换行。
class _RatingTable extends StatelessWidget {
  const _RatingTable({
    required this.columns,
    required this.entries,
    required this.hasReason,
    this.wrapReason = false,
  });

  final List<dynamic> columns;
  final List<dynamic> entries;
  final bool hasReason;
  final bool wrapReason;

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
                (c) =>
                    _cell(Text(c.toString(), style: _headerStyle(cs))),
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
                      // 弹层里给理由列一个上限宽度，长理由才会换行
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text(
                        reason,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                        maxLines: wrapReason ? 3 : 1,
                        overflow: TextOverflow.ellipsis,
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
