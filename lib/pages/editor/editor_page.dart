import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/core/app/site_store.dart';

import 'package:mtbbs/core/app/emoji_loader.dart';
import 'package:mtbbs/core/parser/page_fetcher.dart';
import 'package:mtbbs/core/utils/cache_utils.dart';
import 'package:mtbbs/core/utils/clipboard_helper.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/core/utils/screen_size_ext.dart';
import 'package:mtbbs/api/forum/post/upload.dart' as upload_api;
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/core/utils/shortcut_helper.dart';
import 'package:mtbbs/config/toolbar_config.dart';
import 'package:mtbbs/auth/providers/auth_provider.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/providers/history_provider.dart';
import 'package:mtbbs/models/browse_record.dart';
import 'package:mtbbs/models/editor_snapshot.dart';
import 'package:mtbbs/widgets/bbcode/bbcode_controller.dart';
import 'package:mtbbs/widgets/bbcode/bbcode_toolbar.dart';
import 'package:mtbbs/widgets/common/history_picker.dart';
import 'package:mtbbs/widgets/dialog/emoji_picker_sheet.dart';
import 'package:mtbbs/widgets/dialog/image_picker_sheet.dart';
import 'package:mtbbs/widgets/dialog/attachment_picker_sheet.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';
import 'package:mtbbs/widgets/layout/page_error_widget.dart';
import 'package:mtbbs/widgets/thread/quoted_post_card.dart';
import 'package:mtbbs/providers/editor_history_provider.dart';
import 'package:mtbbs/pages/editor/editor_submit.dart';
import 'package:mtbbs/pages/editor/editor_dialogs.dart';
import 'package:mtbbs/pages/editor/editor_intents.dart';
import 'package:mtbbs/pages/editor/mt_image_sheet.dart';
import 'package:mtbbs/pages/editor/md_import_sheet.dart';
import 'package:mtbbs/services/mt_image_hosting.dart';
import 'package:mtbbs/services/clipboard_paste.dart';
import 'package:mtbbs/widgets/editor/editor_hint_bar.dart';
import 'package:mtbbs/widgets/editor/editor_preview.dart';
import 'package:mtbbs/widgets/editor/editor_line_metrics.dart';
import 'package:mtbbs/widgets/editor/block_marker_gutter.dart';
import 'package:mtbbs/core/parser/bbcode_anchors.dart';
import 'package:mtbbs/core/parser/bbcode_source_lines.dart';
import 'package:mtbbs/core/parser/bbcode_selection_highlight.dart';

part 'editor_media.dart';
part 'editor_pickers.dart';
part 'editor_toolbar_actions.dart';
part 'editor_hints.dart';
part 'editor_page_fetch.dart';
part 'editor_page_changes.dart';
part 'editor_page_actions.dart';
part 'editor_page_layout.dart';
part 'editor_page_locator.dart';

/// 编辑器页面
///
/// 参数（通过 query parameters 传入）：
///   type — post（发帖）/ comment（评论）/ reply（回复评论）
///          / editPost（编辑帖子）/ editReply（编辑评论）
///   tid  — 帖子 ID / pid — 帖子/评论 ID / fid — 版块 ID
class EditorPage extends StatefulWidget {
  final EditorType type;
  final String tid;
  final String pid;
  final String fid;

  const EditorPage({
    super.key,
    required this.type,
    this.tid = '',
    this.pid = '',
    this.fid = '',
  });

  @override
  State<EditorPage> createState() => _EditorPageState();
}

/// 图片管理面板的响应式数据
class _ImageSheetData {
  final List<Map<String, dynamic>> images;
  final bool loading;
  const _ImageSheetData(this.images, this.loading);
}

/// 附件管理面板的响应式数据
class _AttachmentSheetData {
  final List<Map<String, dynamic>> attachments;
  final bool loading;
  const _AttachmentSheetData(this.attachments, this.loading);
}

class _EditorPageState extends State<EditorPage> with WindowListener {
  /// 当前活跃的编辑器实例栈（按打开顺序），仅顶层实例响应窗口关闭，
  /// 防止多开编辑器时底层实例误触发窗口关闭。
  static final List<_EditorPageState> _activeEditors = [];

  /// 窗口关闭处理进行中（防重复弹确认框/重复 close）
  bool _windowCloseInProgress = false;
  // ==================== 核心控制器 ====================
  final _titleCtl = TextEditingController();
  final _contentCtl = BBCodeController();
  final _contentFocusNode = FocusNode();
  final _undoController = UndoHistoryController();

  // ==================== 锚点标记槽 / 跨区定位 ====================
  //
  // 编辑区与预览区各带一个标记槽：当前锚点的标记换成箭头，点标记可跳到另一
  // 个区。两边**共用同一份锚点表**（[_anchors]）——id 就是跨区对应的全部依据，
  // y 只是各自渲染树里的真实位置（编辑区问 RenderEditable，预览区问挂在该
  // 锚点 widget 上的 GlobalKey）。
  //
  // 见 `core/parser/bbcode_anchors.dart` 与 `widgets/editor/editor_preview.dart`。

  /// 当前源码的锚点表（内容变了才重算）
  List<BbAnchor> _anchors = const [];

  /// 编辑区正文容器（标记槽与它共用一个 Stack 坐标系）
  final _editorContentKey = GlobalKey();

  /// 预览面板句柄（用于"点编辑区标记 → 预览定位"）
  final _previewKey = GlobalKey<EditorPreviewState>();
  final _editorScrollCtl = ScrollController();

  /// 编辑区每个锚点的标记位置
  List<BlockMark> _editorMarks = const [];

  /// 两个标记槽共用的"当前锚点"（光标所在锚点；标记槽里显示为箭头）
  int? _activeAnchor;

  String _lastSeenText = '';

  Timer? _gutterMeasureDebounce;
  bool _gutterMeasureScheduled = false;

  /// 最近一次测量时的窗口宽度（用于宽度变化后重算标记位置）
  double? _lastGutterWidth;
  Map<String, String> _emojiMap = {};
  bool _showPreview = false;
  Timer? _previewDebounce;
  final ValueNotifier<EditorPreviewData> _previewData = ValueNotifier(
    const EditorPreviewData.empty(),
  );
  bool _isSubmitting = false;
  bool _loadingPage = false;
  String? _pageError;

  /// 从绑定的 Discuz 页面提取的会话数据
  PageFormData _pageData = const PageFormData();
  Map<String, dynamic>? _quotedPost;
  bool _loadingQuoted = false;
  String? _quotedError;

  /// AID → 图片URL 映射（用于预览时替换 [attachimg]）
  Map<String, String> _aidToSrc = {};

  /// AID → 附件信息映射（用于预览时替换 [attach]）
  Map<String, Map<String, String>> _aidToAttachment = {};

  /// 图片列表（编辑器生命周期内持久，供图片管理面板使用）
  List<Map<String, dynamic>> _imageList = [];
  final Set<String> _ignoredAids = <String>{};
  bool _loadingImages = false;

  /// 响应式数据（图片管理面板通过 ValueListenableBuilder 监听重建）
  final ValueNotifier<_ImageSheetData> _imageSheetDataNotifier = ValueNotifier(
    const _ImageSheetData([], false),
  );

  /// 附件列表（编辑器生命周期内持久，供附件管理面板使用）
  List<Map<String, dynamic>> _attachmentList = [];
  bool _loadingAttachments = false;

  /// 响应式数据（附件管理面板）
  final ValueNotifier<_AttachmentSheetData> _attachmentSheetDataNotifier =
      ValueNotifier(const _AttachmentSheetData([], false));

  late final BBCodeToolbarController _toolbarCtl;
  final MtImageHosting _mtImageHosting = MtImageHosting();
  late final EditorSubmitHelper _submitHelper;

  // ==================== 快照相关 ====================
  late final String _sessionKey;
  String _initialTitle = '';
  String _initialContent = '';
  Set<String> _initialPendingAids = {};
  String _lastSavedTitle = '';
  String _lastSavedContent = '';
  Set<String> _lastSavedPendingAids = {};
  bool _hasUnsavedChanges = false;
  bool _isLeavingNormally = false;
  Timer? _autoSaveTimer;
  bool _initialSnapshotSaved = false;

  // ==================== 提示系统 ====================
  final Set<String> _dismissedHints = {};
  bool _hasEmojiWarning = false;

  bool get _isPost =>
      widget.type == EditorType.post || widget.type == EditorType.editPost;
  bool get _isReply => widget.type == EditorType.reply;
  bool get _isEdit =>
      widget.type == EditorType.editPost || widget.type == EditorType.editReply;

  String get _pageTitle {
    switch (widget.type) {
      case EditorType.post:
        final name =
            SiteStore.instance.forums[widget.fid] ?? '版块 ${widget.fid}';
        return '发帖 - $name';
      case EditorType.editPost:
        return '编辑帖子';
      case EditorType.comment:
        return '评论';
      case EditorType.editReply:
        return '编辑评论';
      case EditorType.reply:
        return '回复评论';
    }
  }

  @override
  void initState() {
    super.initState();
    _sessionKey = EditorHistoryProvider.generateKey(
      widget.type,
      tid: widget.tid,
      pid: widget.pid,
    );

    // 初始化表情映射
    _emojiMap = Map<String, String>.from(EmojiService().map);

    _submitHelper = EditorSubmitHelper(
      context: context,
      editorType: widget.type,
      widgetFid: widget.fid,
      widgetTid: widget.tid,
      widgetPid: widget.pid,
      titleCtl: _titleCtl,
      contentCtl: _contentCtl,
      isEdit: _isEdit,
      isPost: _isPost,
      isReply: _isReply,
    );

    _toolbarCtl = BBCodeToolbarController(onAction: _handleToolbarAction);
    _titleCtl.addListener(_onContentChanged);
    _contentCtl.addListener(_onContentChanged);
    // 光标/选区变化 → 更新标记槽与（必要时）预览定位
    _contentCtl.addListener(_onEditingChanged);
    _lastSeenText = _contentCtl.text;
    _anchors = bbAnchors(_lastSeenText);

    _doFetchPage();

    if (_isReply && widget.tid.isNotEmpty && widget.pid.isNotEmpty) {
      _doFetchQuotedPost();
    }

    // Windows：拦截窗口关闭（标题栏 X / Alt+F4），复用返回确认逻辑
    if (Platform.isWindows) {
      _activeEditors.add(this);
      windowManager.addListener(this);
      windowManager.setPreventClose(true);
    }

    // 快照：检查未清理的会话 → 添加到顶栏提示
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final historyProv = context.read<EditorHistoryProvider>();
      if (historyProv.hasSession(_sessionKey)) {
        _addHint('unexpected_close', '上次编辑器意外关闭，可在编辑历史中恢复');
      }
    });
  }

  void _focusContent() => _contentFocusNode.requestFocus();

  /// setState 安全包装：part 文件中的扩展方法无法访问 @protected 的 setState，
  /// 统一通过本方法触发重建（自带 mounted 判断）。
  void _setState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  @override
  void dispose() {
    _titleCtl.removeListener(_onContentChanged);
    _contentCtl.removeListener(_onContentChanged);
    _contentCtl.removeListener(_onEditingChanged);
    _titleCtl.dispose();
    _contentCtl.dispose();
    _contentFocusNode.dispose();
    _undoController.dispose();
    _editorScrollCtl.dispose();
    _gutterMeasureDebounce?.cancel();
    _previewDebounce?.cancel();
    _previewData.dispose();
    _autoSaveTimer?.cancel();
    if (!_isLeavingNormally && _hasUnsavedChanges) {
      try {
        _saveAutoSnapshot();
      } catch (_) {}
    }
    if (Platform.isWindows) {
      windowManager.removeListener(this);
      _activeEditors.remove(this);
      if (_activeEditors.isEmpty) {
        windowManager.setPreventClose(false);
      }
    }
    super.dispose();
  }

  /// Windows 窗口关闭事件（标题栏 X / Alt+F4 / taskbar close）。
  /// 仅顶层编辑器实例响应：弹确认框 → 通过则放行关闭，否则维持拦截。
  @override
  void onWindowClose() async {
    if (_windowCloseInProgress) return;
    if (_activeEditors.isEmpty || !identical(_activeEditors.last, this)) {
      return;
    }
    _windowCloseInProgress = true;
    final ok = await _requestExit();
    if (!ok) {
      _windowCloseInProgress = false; // 用户取消，恢复拦截
      return;
    }
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  // ==================== Build ====================

  @override
  Widget build(BuildContext context) => _buildPage(context);
}
