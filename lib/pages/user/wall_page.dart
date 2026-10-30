import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/api/home/wall/export.dart' as wall_api;
import 'package:mtbbs/auth/providers/auth_provider.dart';
import 'package:mtbbs/config/toolbar_config.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/models/wall_comment.dart';
import 'package:mtbbs/pages/editor/mt_image_sheet.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/services/mt_image_hosting.dart';
import 'package:mtbbs/widgets/bbcode/bbcode_controller.dart';
import 'package:mtbbs/widgets/bbcode/post_html_widget.dart';
import 'package:mtbbs/widgets/common/page_actions.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';
import 'package:mtbbs/widgets/common/user_avatar.dart';
import 'package:mtbbs/widgets/editor/mini_editor_bar.dart';
import 'package:mtbbs/widgets/layout/page_error_widget.dart';
import 'package:mtbbs/widgets/layout/pagination_bar.dart';
import 'package:mtbbs/widgets/layout/state_views.dart';

/// 用户留言板页面
///
/// 路径：`/user/:uid/wall`（`uid == 'self'` 或空 = 当前登录用户）。
/// 只走 PC 模板（见 `lib/api/home/wall/http.dart`）。支持留言发布、编辑、
/// 回复、删除——各操作的可见性由 API 解析出的 `canEdit/canDelete/canReply`
/// 决定（页面不写死权限）。
///
/// 发布使用与帖子页同源的 [MiniEditorBar]（撤销/重做、BBCode 工具栏、表情、
/// MT 图床、预览）；字数上限取设置项「站点字数限制」。
///
/// 注意：Discuz 的「回复」会把回复**投递到被引留言作者的留言板**（跨墙），
/// 因此回复入口文案带「回复到 TA 的留言板」提示。
class WallPage extends StatefulWidget {
  final String uid;
  final String nickname;

  /// 初始页码（从站内 URL 深链进入时携带）
  final int initialPage;

  const WallPage({
    super.key,
    required this.uid,
    this.nickname = '',
    this.initialPage = 1,
  });

  @override
  State<WallPage> createState() => _WallPageState();
}

class _WallPageState extends State<WallPage> {
  late String _uid;
  final List<WallComment> _comments = [];
  final _composerCtl = BBCodeController();
  final _mtImageHosting = MtImageHosting();

  String _formhash = '';
  bool _canPost = false;
  int _page = 1;
  int _totalPages = 1;
  bool _loading = false;
  bool _busy = false;
  String? _error;

  int get _maxLength => context.read<SettingsProvider>().postMaxLength;

  @override
  void initState() {
    super.initState();
    final raw = widget.uid;
    _uid = (raw.isEmpty || raw == 'self')
        ? context.read<AuthProvider>().uid
        : raw;
    _load();
  }

  @override
  void dispose() {
    _composerCtl.dispose();
    super.dispose();
  }

  String get _title =>
      widget.nickname.isNotEmpty ? '${widget.nickname}的留言板' : '留言板';

  String get _pageUrl =>
      '${SiteStore.instance.baseUrl}/home.php?mod=space&uid=$_uid&do=wall';

  Future<void> _load() => _fetch(widget.initialPage);

  Future<void> _fetch(int page) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await wall_api.getWall(
        ApiService().dio,
        uid: _uid,
        page: page,
      );
      if (!mounted) return;
      if (result['success'] != true) {
        setState(() {
          if (_comments.isEmpty) {
            _error = result['message'] as String? ?? '加载失败';
          }
          _loading = false;
        });
        return;
      }
      setState(() {
        _comments
          ..clear()
          ..addAll(
            ((result['comments'] as List<dynamic>?) ?? const []).map(
              (e) => WallComment.fromMap(Map<String, dynamic>.from(e as Map)),
            ),
          );
        _formhash = result['formhash'] as String? ?? '';
        _canPost = result['canPost'] == true;
        _page = (result['currentPage'] as num?)?.toInt() ?? page;
        _totalPages = (result['totalPages'] as num?)?.toInt() ?? 1;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      AppLogger.w('PAGE', 'WallPage error: $e');
      setState(() {
        if (_comments.isEmpty) _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _refresh() => _fetch(_page);

  void _goToPage(int page) {
    if (page == _page) return;
    _fetch(page);
  }

  /// 提交发布留言（工具栏按钮触发）
  Future<void> _postComment() async {
    final text = _composerCtl.text.trim();
    if (text.isEmpty) return;
    if (!_ensureLoggedIn()) return;
    setState(() => _busy = true);
    try {
      final r = await wall_api.postWallComment(
        ApiService().dio,
        uid: _uid,
        formhash: _formhash,
        message: text,
      );
      if (!mounted) return;
      if (r.success) {
        _composerCtl.clear();
        showToast('留言成功');
        await _refresh();
      } else {
        showToast(r.message.isNotEmpty ? r.message : '操作失败');
      }
    } catch (e) {
      AppLogger.w('PAGE', 'WallPage post error: $e');
      if (mounted) showToast('操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _ensureLoggedIn() {
    if (_formhash.isEmpty) {
      showToast('登录状态失效，请重新登录');
      return false;
    }
    return true;
  }

  /// 编辑自己的留言
  Future<void> _editComment(WallComment c) {
    return _openEditorSheet(
      title: '编辑留言',
      initial: c.message,
      submitLabel: '保存',
      onSubmit: (text) async {
        try {
          final r = await wall_api.editWallComment(
            ApiService().dio,
            uid: _uid,
            cid: c.cid,
            formhash: _formhash,
            message: text,
          );
          if (!mounted) return false;
          if (r.success) {
            showToast('修改成功');
            await _refresh();
          } else {
            showToast(r.message.isNotEmpty ? r.message : '操作失败');
          }
          return r.success;
        } catch (e) {
          AppLogger.w('PAGE', 'WallPage edit error: $e');
          if (mounted) showToast('操作失败：$e');
          return false;
        }
      },
    );
  }

  /// 回复某条留言（Discuz 会投递到被引作者的留言板）
  Future<void> _replyComment(WallComment c) {
    return _openEditorSheet(
      title: '回复 @${c.authorName}（将发布到 TA 的留言板）',
      initial: '',
      submitLabel: '回复',
      onSubmit: (text) async {
        try {
          final r = await wall_api.replyWallComment(
            ApiService().dio,
            uid: _uid,
            cid: c.cid,
            formhash: _formhash,
            message: text,
          );
          if (!mounted) return false;
          if (r.success) {
            showToast('回复成功');
            await _refresh();
          } else {
            showToast(r.message.isNotEmpty ? r.message : '操作失败');
          }
          return r.success;
        } catch (e) {
          AppLogger.w('PAGE', 'WallPage reply error: $e');
          if (mounted) showToast('操作失败：$e');
          return false;
        }
      },
    );
  }

  Future<void> _deleteComment(WallComment c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除留言'),
        content: const Text('确定删除这条留言吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!_ensureLoggedIn()) return;
    setState(() => _busy = true);
    try {
      final r = await wall_api.deleteWallComment(
        ApiService().dio,
        cid: c.cid,
        formhash: _formhash,
      );
      if (!mounted) return;
      if (r.success) {
        showToast('已删除');
        await _refresh();
      } else {
        showToast(r.message.isNotEmpty ? r.message : '操作失败');
      }
    } catch (e) {
      AppLogger.w('PAGE', 'WallPage delete error: $e');
      if (mounted) showToast('操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 弹出底部迷你编辑器（编辑 / 回复共用）
  Future<void> _openEditorSheet({
    required String title,
    required String initial,
    required String submitLabel,
    required Future<bool> Function(String text) onSubmit,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => _WallEditorSheet(
        title: title,
        initial: initial,
        submitLabel: submitLabel,
        maxLength: _maxLength,
        hosting: _mtImageHosting,
        onSubmit: onSubmit,
      ),
    );
  }

  /// 插入 MT 图床外链
  void _showMtImage(BBCodeController ctl) {
    showMtImageSheet(
      context,
      hosting: _mtImageHosting,
      onInsert: (bbcode) => ctl.wrapInline('', '', ' $bbcode '),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          PageActions(
            url: _pageUrl,
            onRefresh: _loading ? null : _refresh,
            loading: _loading,
            copyLabel: '复制留言板链接',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          if (_totalPages > 1 && !_loading && _error == null)
            BottomPaginationBar(
              page: _page,
              totalPages: _totalPages,
              onGoToPage: _goToPage,
            ),
          if (_canPost) _buildMiniEditor(),
        ],
      ),
    );
  }

  /// 底部迷你编辑器（与帖子页同源：撤销/重做、工具栏、表情、MT 图床、预览）
  Widget _buildMiniEditor() {
    return MiniEditorBar(
      contentCtl: _composerCtl,
      toolbarContext: MiniToolbarContext.wall,
      hintText: '写下你的留言…',
      submitting: _busy,
      maxLength: _maxLength,
      onSubmit: _postComment,
      onMtImage: () => _showMtImage(_composerCtl),
    );
  }

  Widget _buildBody() {
    if (_loading && _comments.isEmpty) return const LoadingView();
    if (_error != null) {
      return PageErrorWidget(message: _error!, onRetry: _load);
    }
    if (_comments.isEmpty) {
      return const EmptyView(icon: Icons.forum_outlined, text: '暂无留言');
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _comments.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) => _buildComment(_comments[index]),
      ),
    );
  }

  Widget _buildComment(WallComment c) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(uid: c.authorUid, nickname: c.authorName, radius: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        c.authorName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      c.time,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (c.hasQuote) ...[const SizedBox(height: 4), _buildQuote(c)],
                const SizedBox(height: 4),
                PostHtmlWidget(bbcode: c.message, fontSize: 14),
                _buildActions(c),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuote(WallComment c) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: cs.outlineVariant, width: 3)),
      ),
      child: Text(
        '${c.quotedUser}: ${c.quotedText}',
        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// 操作行：按解析出的权限展示编辑 / 删除 / 回复
  Widget _buildActions(WallComment c) {
    if (!c.canEdit && !c.canDelete && !c.canReply) {
      return const SizedBox.shrink();
    }
    return Row(
      children: [
        if (c.canEdit) _action('编辑', () => _editComment(c)),
        if (c.canDelete) _action('删除', () => _deleteComment(c)),
        if (c.canReply) _action('回复', () => _replyComment(c)),
      ],
    );
  }

  Widget _action(String label, VoidCallback onTap) {
    return TextButton(
      onPressed: _busy ? null : onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

/// 留言板底部弹出式迷你编辑器（编辑 / 回复复用同一个编辑器表面）
class _WallEditorSheet extends StatefulWidget {
  const _WallEditorSheet({
    required this.title,
    required this.initial,
    required this.submitLabel,
    required this.maxLength,
    required this.hosting,
    required this.onSubmit,
  });

  final String title;
  final String initial;
  final String submitLabel;
  final int maxLength;
  final MtImageHosting hosting;

  /// 返回 true 表示提交成功（关闭弹窗）
  final Future<bool> Function(String text) onSubmit;

  @override
  State<_WallEditorSheet> createState() => _WallEditorSheetState();
}

class _WallEditorSheetState extends State<_WallEditorSheet> {
  late final BBCodeController _ctl;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _ctl = BBCodeController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _ctl.text.trim();
    if (text.isEmpty) return;
    setState(() => _submitting = true);
    final ok = await widget.onSubmit(text);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) Navigator.pop(context);
  }

  void _showMtImage() {
    showMtImageSheet(
      context,
      hosting: widget.hosting,
      onInsert: (bbcode) => _ctl.wrapInline('', '', ' $bbcode '),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: '关闭',
                  onPressed: _submitting ? null : () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          MiniEditorBar(
            contentCtl: _ctl,
            toolbarContext: MiniToolbarContext.wall,
            hintText: '输入内容…',
            submitting: _submitting,
            autofocus: true,
            maxLength: widget.maxLength,
            submitLabel: widget.submitLabel,
            onSubmit: _submit,
            onMtImage: _showMtImage,
          ),
        ],
      ),
    );
  }
}
