import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/config/brand_colors.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/models/thread_detail.dart';
import 'package:mtbbs/pages/share/share_image_page.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/bbcode/post_html_widget.dart';
import 'package:mtbbs/widgets/common/user_avatar.dart';
import 'package:mtbbs/widgets/share/share_qr_code.dart';

/// 楼层 / 评论「生成图片」入口。
///
/// 预览与保存由 [ShareImagePage] 提供；本文件只负责**帖子卡**的渲染
/// （作者信息 + 正文 + 评分/打赏记录 + 页脚定位信息）。
class ThreadSharePage {
  ThreadSharePage._();

  static Future<void> open(
    BuildContext context, {
    required PostItem post,
    required String tid,
    String threadTitle = '',
    String opUid = '',
  }) {
    final settings = context.read<SettingsProvider>();
    // 「只生成内容图」：只出正文，去掉作者信息 / 评分 / 页脚（此时不显示勾选项）
    final contentOnly = settings.shareImageContentOnly;
    final id = post.pid.isNotEmpty ? post.pid : tid;
    return ShareImagePage.open(
      context,
      filePrefix: 'MTBBS_$id',
      toggles: contentOnly
          ? const []
          : [
              const ShareToggle(id: 'rating', label: '渲染评分'),
              ShareToggle(
                id: 'truncate',
                label: '截断(${settings.shareImageMaxHeight}px)',
              ),
              const ShareToggle(id: 'qr', label: '渲染二维码'),
            ],
      cardBuilder: (ctx, enabled) => _ShareCard(
        post: post,
        tid: tid,
        threadTitle: threadTitle,
        opUid: opUid,
        contentOnly: contentOnly,
        renderRating: enabled.contains('rating'),
        renderQr: enabled.contains('qr'),
        // 「只生成内容图」下沿用截断（与旧行为一致）；否则跟随「截断」勾选
        maxBodyHeight: (contentOnly || enabled.contains('truncate'))
            ? settings.shareImageMaxHeight.toDouble()
            : null,
      ),
    );
  }
}

/// 分享卡本体（强制浅色）：作者信息 + 正文 + 评分/打赏 + 来源 / 定位信息水印。
class _ShareCard extends StatelessWidget {
  final PostItem post;
  final String threadTitle;
  final String opUid;
  final String tid;

  /// 正文高度上限（逻辑像素）；null = 不限制（生成完整长图）
  final double? maxBodyHeight;

  /// 是否渲染评分 / 打赏区块
  final bool renderRating;

  /// 是否渲染右下角二维码
  final bool renderQr;

  /// 只输出正文（不含作者信息 / 评分、页脚与定位信息）
  final bool contentOnly;

  const _ShareCard({
    required this.post,
    required this.threadTitle,
    required this.opUid,
    required this.tid,
    this.maxBodyHeight,
    this.renderRating = true,
    this.renderQr = true,
    this.contentOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!contentOnly) ...[
            _header(context, cs),
            const SizedBox(height: 12),
            Divider(height: 1, color: cs.outlineVariant),
            const SizedBox(height: 12),
          ],
          _buildBody(),
          if (!contentOnly && renderRating && post.rating != null) ...[
            const SizedBox(height: 12),
            _RatingSection(rating: post.rating!),
          ],
          if (!contentOnly) ...[
            const SizedBox(height: 16),
            _footer(context, cs),
          ],
        ],
      ),
    );
  }

  /// 正文：只读渲染（关交互 / 选区）；开启长度限制时裁切并加"查看原帖"提示
  Widget _buildBody() {
    final body = IgnorePointer(
      child: PostHtmlWidget(
        bbcode: post.bbcode,
        selectable: false,
        disabledTags: const <String>{},
      ),
    );
    final limit = maxBodyHeight;
    if (limit == null) return body;
    return _ClampedBody(
      maxHeight: limit,
      hint: '内容过长，此处已截断 · 完整内容见原帖 / 该楼层（${_locator()}）',
      child: body,
    );
  }

  Widget _header(BuildContext context, ColorScheme cs) {
    final isOp = post.isOp || (post.uid.isNotEmpty && post.uid == opUid);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        UserAvatar(uid: post.uid, nickname: post.username, radius: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      post.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (post.usergroup.isNotEmpty)
                    _badge(
                      post.usergroup,
                      levelColor,
                      levelColor.withValues(alpha: 0.12),
                    ),
                  if (isOp) _badge('楼主', cs.onPrimary, cs.primary),
                ],
              ),
              if (post.postTime.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    post.postTime,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ),
              if (post.ipLocation.isNotEmpty)
                Text(
                  post.ipLocation,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
            ],
          ),
        ),
        if (!post.isOp && post.floor > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              post.floorText,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  Widget _footer(BuildContext context, ColorScheme cs) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.asset('assets/icon/app_icon.png', width: 24, height: 24),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MTBBS · ${SiteStore.instance.host}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (threadTitle.isNotEmpty)
                Text(
                  threadTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
              Text(
                _locator(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        if (renderQr) ...[
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShareQrCode(data: _qrUrl),
              const SizedBox(height: 2),
              Text(
                '扫码直达',
                style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// 二维码内容：帖子的 findpost 直达链接（无 pid 时退回帖子链接）
  String get _qrUrl {
    final base = SiteStore.instance.baseUrl;
    if (post.pid.isNotEmpty) {
      return '$base/forum.php?mod=redirect&goto=findpost'
          '&ptid=$tid&pid=${post.pid}';
    }
    return '$base/forum.php?mod=viewthread&tid=$tid';
  }

  /// 站内定位信息：tid + pid（+ 楼层），凭此可在论坛定位到该楼
  String _locator() {
    final parts = <String>['tid=$tid'];
    if (post.pid.isNotEmpty) parts.add('pid=${post.pid}');
    if (post.floor > 0) parts.add(post.floorText);
    return parts.join('   ·   ');
  }

  Widget _badge(String text, Color textColor, Color bgColor) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(text, style: TextStyle(fontSize: 10, color: textColor)),
      ),
    );
  }
}

/// 「评分记录 / 打赏」区块：列出对该楼打分（打赏）的用户、各维度分值与理由。
///
/// 数据来自 `PostItem.rating`（`core/parser/post_parser.dart` 解析的 `viewratings` 记录）。
class _RatingSection extends StatelessWidget {
  final Map<String, dynamic> rating;

  const _RatingSection({required this.rating});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final totalScore = rating['totalScore'] as String? ?? '';
    final columns = rating['columns'] as List<dynamic>? ?? [];
    final entries = rating['entries'] as List<dynamic>? ?? [];
    if (columns.isEmpty && entries.isEmpty) return const SizedBox.shrink();
    final hasReason = entries.any(
      (e) => ((e as Map)['reason'] as String? ?? '').isNotEmpty,
    );

    TextStyle headerStyle() => TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: cs.onSurfaceVariant,
    );
    TextStyle cellStyle() =>
        TextStyle(fontSize: 11, color: cs.onSurfaceVariant);

    Widget cell(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: child,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                '评分记录',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
              if (totalScore.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  totalScore,
                  style: TextStyle(fontSize: 12, color: cs.primary),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              border: TableBorder.all(color: cs.outlineVariant, width: 0.5),
              defaultColumnWidth: const IntrinsicColumnWidth(),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  decoration: BoxDecoration(color: cs.surfaceContainerHighest),
                  children: [
                    cell(Text('用户', style: headerStyle())),
                    ...columns.map(
                      (c) => cell(Text(c.toString(), style: headerStyle())),
                    ),
                    if (hasReason) cell(Text('理由', style: headerStyle())),
                  ],
                ),
                ...entries.map((e) {
                  final m = e as Map;
                  final username = m['username'] as String? ?? '';
                  final uid = m['uid'] as String? ?? '';
                  final scores = m['scores'] as List<dynamic>? ?? [];
                  final reason = m['reason'] as String? ?? '';
                  return TableRow(
                    children: [
                      cell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            UserAvatar(uid: uid, nickname: username, radius: 9),
                            const SizedBox(width: 4),
                            Text(username, style: cellStyle()),
                          ],
                        ),
                      ),
                      ...scores.map(
                        (s) => cell(Text(s.toString(), style: cellStyle())),
                      ),
                      if (hasReason)
                        cell(
                          Text(
                            reason,
                            style: cellStyle(),
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
}

/// 正文高度限制：超过 [maxHeight] 时裁切，并在底部渐隐 + 提示"查看原帖"。
///
/// 用不可滚动的 `SingleChildScrollView` 天然得到「短内容原样、长内容裁到 [maxHeight]」，
/// 再靠 `maxScrollExtent > 0` 判断是否真的发生了截断（决定要不要画渐隐条）。
class _ClampedBody extends StatefulWidget {
  final double maxHeight;
  final String hint;
  final Widget child;

  const _ClampedBody({
    required this.maxHeight,
    required this.hint,
    required this.child,
  });

  @override
  State<_ClampedBody> createState() => _ClampedBodyState();
}

class _ClampedBodyState extends State<_ClampedBody> {
  final ScrollController _controller = ScrollController();
  bool _truncated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_check);
  }

  @override
  void didUpdateWidget(covariant _ClampedBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.maxHeight != widget.maxHeight) {
      WidgetsBinding.instance.addPostFrameCallback(_check);
    }
  }

  void _check(Duration _) {
    if (!mounted || !_controller.hasClients) return;
    final truncated = _controller.position.maxScrollExtent > 0;
    if (truncated != _truncated) setState(() => _truncated = truncated);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      child: Stack(
        children: [
          SingleChildScrollView(
            controller: _controller,
            physics: const NeverScrollableScrollPhysics(),
            child: widget.child,
          ),
          if (_truncated)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 渐隐：把被裁断的文字淡入卡片底色，避免生硬的切口
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [cs.surface.withValues(alpha: 0), cs.surface],
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    color: cs.surface,
                    padding: const EdgeInsets.only(top: 2, bottom: 6),
                    child: Text(
                      widget.hint,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
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
    );
  }
}
