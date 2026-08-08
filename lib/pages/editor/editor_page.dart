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
import 'package:mtbbs/services/mt_image_hosting.dart';
import 'package:mtbbs/services/clipboard_paste.dart';
import 'package:mtbbs/widgets/editor/editor_hint_bar.dart';
import 'package:mtbbs/widgets/editor/editor_preview.dart';

part 'editor_media.dart';
part 'editor_pickers.dart';
part 'editor_toolbar_actions.dart';
part 'editor_hints.dart';

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
  Map<String, String> _emojiMap = {};
  bool _showPreview = false;
  Timer? _previewDebounce;
  final ValueNotifier<EditorPreviewData> _previewData = ValueNotifier(
    const EditorPreviewData('', ''),
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

  // ==================== 页面加载 ====================

  Future<void> _doFetchPage({bool preserveContent = false}) async {
    setState(() {
      _loadingPage = true;
      _pageError = null;
    });
    final result = await _submitHelper.fetchPage(
      preserveContent: preserveContent,
    );
    if (!mounted) return;

    AppLogger.i(
      'EDITOR',
      jsonEncode({
        'type': 'page_loaded',
        'success': result.success,
        'formhash': result.formhash.isNotEmpty,
        'titleLen': result.title.length,
        'contentLen': result.content.length,
        'images': result.images.length,
        'boundAttachments': result.boundAttachments.length,
        'uploadHash': result.uploadHash.isNotEmpty,
        'fid': result.fid,
        'tid': result.tid,
        'pid': result.pid,
      }),
    );

    if (!result.success) {
      // 自检开关关闭时，忽略所有启动报错，无条件进入预览模式
      if (!context.read<SettingsProvider>().editorStartupCheck) {
        AppLogger.i('EDITOR', 'startup check disabled — entering preview mode');
        setState(() {
          _loadingPage = false;
          _pageError = null;
          _pageData = const PageFormData(success: true);
        });
        return;
      }
      setState(() {
        _loadingPage = false;
        _pageError = result.error ?? '加载失败';
      });
      return;
    }

    bool shouldSaveInitial = false;
    setState(() {
      _pageData = result;
      _loadingPage = false;
      _pageError = null;
      // 同步填充 AID→URL 映射和图片列表
      if (preserveContent) {
        // 保留模式：合并新数据，已有的快照数据不被覆盖
        for (final img in result.images) {
          final aid = img['aid'];
          final src = img['src'];
          if (aid != null && src != null && aid.isNotEmpty && src.isNotEmpty) {
            _aidToSrc[aid] = src;
          }
        }
      } else {
        _aidToSrc = {
          for (final img in result.images)
            if (img['aid'] != null && img['src'] != null)
              img['aid']!: img['src']!,
        };
      }
      _imageList = result.images.map((img) {
        return <String, dynamic>{
          'aid': img['aid'] ?? '',
          'src': img['src'] ?? '',
          'title': img['title'] ?? '',
          'type': 'existing',
        };
      }).toList();
      // 同步填充已绑定附件映射
      _aidToAttachment = {
        for (final att in result.boundAttachments)
          att['aid'] as String: {
            'name': att['filename'] ?? '',
            'size': att['size'] ?? '',
            'url': 'forum.php?mod=attachment&aid=${att['aid'] ?? ''}',
          },
      };
      if (_isEdit && !preserveContent) {
        if (result.title.isNotEmpty) _titleCtl.text = result.title;
        if (result.content.isNotEmpty) _contentCtl.text = result.content;
        if (result.title.isNotEmpty || result.content.isNotEmpty) {
          shouldSaveInitial = true;
        }
      }
    });
    _syncImagesNotifier();

    if (!preserveContent) {
      _initialTitle = _titleCtl.text;
      _initialContent = _contentCtl.text;
      _initialPendingAids = Set.from(_contentCtl.pendingAids);
      _updateHasChanges();
      _updateLastSaved();
    }

    if (shouldSaveInitial && !_initialSnapshotSaved) {
      _initialSnapshotSaved = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _saveManualSnapshot();
      });
    }

    // 异步加载已上传但未绑定的图片和附件
    _refreshImageList();
    _refreshAttachmentList();
  }

  Future<void> _doFetchQuotedPost() async {
    setState(() {
      _loadingQuoted = true;
      _quotedError = null;
    });
    final post = await _submitHelper.fetchQuotedPost();
    if (!mounted) return;
    if (post != null) {
      setState(() {
        _quotedPost = post;
        _loadingQuoted = false;
      });
    } else {
      setState(() {
        _quotedError = '获取失败';
        _loadingQuoted = false;
      });
    }
  }

  // ==================== 内容监听 ====================

  void _onContentChanged() {
    if (mounted) setState(() {});
    _updateHasChanges();
    _updateEmojiWarning();
    _resetAutoSaveTimer();
    _schedulePreviewUpdate();
  }

  void _schedulePreviewUpdate() {
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final title = _titleCtl.text.trim();
      final content = _contentCtl.text.trim();
      final processed = _preparePreviewBbcode(content);
      final newData = EditorPreviewData(title, processed);
      if (_previewData.value.title != newData.title ||
          _previewData.value.content != newData.content) {
        _previewData.value = newData;
      }
    });
  }

  void _updateHasChanges() {
    final titleChanged =
        _titleCtl.text != _initialTitle && _titleCtl.text.isNotEmpty;
    final contentChanged = _contentCtl.text != _initialContent;
    final aidsChanged = !_setEquals(
      _contentCtl.pendingAids,
      _initialPendingAids,
    );
    _hasUnsavedChanges = titleChanged || contentChanged || aidsChanged;
  }

  bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    return a.every(b.contains);
  }

  void _updateLastSaved() {
    _lastSavedTitle = _titleCtl.text;
    _lastSavedContent = _contentCtl.text;
    _lastSavedPendingAids = Set.from(_contentCtl.pendingAids);
  }

  bool get _hasChangesSinceLastSave {
    if (_titleCtl.text != _lastSavedTitle && _titleCtl.text.isNotEmpty)
      return true;
    if (_contentCtl.text != _lastSavedContent) return true;
    if (!_setEquals(_contentCtl.pendingAids, _lastSavedPendingAids))
      return true;
    return false;
  }

  // ==================== 自动保存 ====================

  void _resetAutoSaveTimer() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(
      context.read<EditorHistoryProvider>().autoSaveInterval,
      (_) => _saveAutoSnapshot(),
    );
  }

  void _saveAutoSnapshot() {
    if (!_hasUnsavedChanges || !_hasChangesSinceLastSave) return;
    final snapshot = _buildSnapshot(isManual: false);
    context.read<EditorHistoryProvider>().addAutoSnapshot(snapshot);
    _updateLastSaved();
    AppLogger.d('EDITOR', 'auto-snapshot saved: ${snapshot.wordCount} chars');
  }

  Future<void> _saveManualSnapshot() async {
    final snapshot = _buildSnapshot(isManual: true);
    await context.read<EditorHistoryProvider>().addManualSnapshot(snapshot);
    _updateLastSaved();
    AppLogger.i('EDITOR', 'manual snapshot saved: ${snapshot.wordCount} chars');
    if (mounted) showToast('已手动保存');
  }

  EditorSnapshot _buildSnapshot({required bool isManual}) {
    return EditorSnapshot(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      sessionKey: _sessionKey,
      editorType: widget.type.name,
      label: _pageTitle,
      title: _titleCtl.text,
      content: _contentCtl.text,
      pendingAids: _contentCtl.pendingAids.toList(),
      quotedPost: _quotedPost?.map((k, v) => MapEntry(k, v.toString())),
      createdAt: DateTime.now(),
      isManual: isManual,
      tid: widget.tid,
      pid: widget.pid,
      fid: widget.fid,
      pageData: PageFormDataSnapshot.fromPageFormData(_pageData),
      emojiMap: Map.from(_emojiMap),
    );
  }

  void _focusContent() => _contentFocusNode.requestFocus();

  /// setState 安全包装：part 文件中的扩展方法无法访问 @protected 的 setState，
  /// 统一通过本方法触发重建（自带 mounted 判断）。
  void _setState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  /// 请求退出编辑器，处理未保存内容。
  /// 返回 true 确认退出，false 取消。
  Future<bool> _requestExit() async {
    if (!_hasUnsavedChanges) return true;
    final minWords = context.read<EditorHistoryProvider>().minSnapshotWordCount;
    final totalWords =
        _titleCtl.text.trim().length + _contentCtl.text.trim().length;
    if (totalWords < minWords) return true;
    final shouldPop = await showExitConfirmDialog(context);
    if (shouldPop == 'save') {
      await _saveManualSnapshot();
      return true;
    }
    return shouldPop == 'discard';
  }

  // ==================== 提交 ====================

  Future<void> _submit() async {
    final title = _titleCtl.text.trim();
    final content = _contentCtl.text.trim();
    if (content.isEmpty) {
      if (mounted) showToast('请输入内容');
      return;
    }
    if (widget.type == EditorType.post && title.isEmpty) {
      if (mounted) showToast('请输入标题');
      return;
    }
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      if (mounted) {
        showToast('请先登录');
      }
      return;
    }
    if (_isEdit &&
        (!_pageData.formhash.isNotEmpty || !_pageData.posttime.isNotEmpty)) {
      if (mounted) {
        showToast('页面数据未加载，请稍后');
      }
      return;
    }

    setState(() => _isSubmitting = true);

    AppLogger.i(
      'EDITOR',
      jsonEncode({
        'action': 'submit',
        'type': widget.type.name,
        'titleLen': title.length,
        'contentLen': content.length,
        'formhash': _pageData.formhash.isNotEmpty,
        'posttime': _pageData.posttime.isNotEmpty,
      }),
    );

    try {
      final result = await _submitHelper.submit(_pageData, title, content);
      if (!mounted) return;
      if (result.success) {
        final msg = result.needsApproval ? '需要审核' : '操作成功';
        AppLogger.i(
          'EDITOR',
          jsonEncode({
            'action': 'submit_done',
            'success': true,
            'needsApproval': result.needsApproval,
            'type': widget.type.name,
          }),
        );
        showToast(msg);
        _isLeavingNormally = true;
        _autoSaveTimer?.cancel();
        context.read<EditorHistoryProvider>().markSubmitted(_sessionKey);
        Navigator.of(context).pop({'success': true, 'result': result});
      } else {
        setState(() => _isSubmitting = false);
        AppLogger.w(
          'EDITOR',
          jsonEncode({
            'action': 'submit_done',
            'success': false,
            'error': result.message,
          }),
        );
        showToast('操作失败: ${result.message}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        AppLogger.e(
          'EDITOR',
          jsonEncode({'action': 'submit_error', 'error': e.toString()}),
        );
        showToast('网络错误: $e');
      }
    }
  }

  // ==================== 快照方法 ====================

  Future<void> _openHistoryPage() async {
    final result = await context.push<Map<String, dynamic>>(
      '/editor/history?key=$_sessionKey',
    );
    if (result == null || !mounted) return;
    final action = result['action'] as String?;
    if (action == 'restore') {
      final snapshotId = result['snapshotId'] as String?;
      if (snapshotId != null) _restoreSnapshot(snapshotId);
    }
  }

  void _restoreSnapshot(String snapshotId) {
    final historyProv = context.read<EditorHistoryProvider>();
    final snapshot = historyProv.getSnapshotById(snapshotId);
    if (snapshot == null) {
      showToast('快照不存在');
      return;
    }

    // 校验编辑器类型一致性，防止跨类型恢复导致 fid/tid/pid 错乱
    if (snapshot.editorType != widget.type.name) {
      if (!mounted) return;
      showToast(
        '无法恢复：快照类型为"${_typeLabel(snapshot.editorType)}"，'
        '当前为"$_pageTitle"',
      );
      return;
    }

    _saveManualSnapshot();
    _titleCtl.text = snapshot.title;
    _contentCtl.text = snapshot.content;
    _contentCtl.pendingAids = snapshot.pendingAids.toSet();
    _pageData = snapshot.pageData.toPageFormData();

    // 从快照预填充图片/附件映射（供恢复后预览使用，
    // _doFetchPage 后若新页面无这些图片，再兜底合并）
    for (final img in snapshot.pageData.images) {
      final aid = img['aid'];
      final src = img['src'];
      if (aid != null && src != null && aid.isNotEmpty && src.isNotEmpty) {
        _aidToSrc[aid] = src;
      }
    }

    if (snapshot.quotedPost != null) {
      _quotedPost = snapshot.quotedPost!.map(
        (k, v) => MapEntry(k, v as dynamic),
      );
    }
    if (snapshot.emojiMap.isNotEmpty) {
      _emojiMap = Map.from(snapshot.emojiMap);
    }
    _initialTitle = snapshot.title;
    _initialContent = snapshot.content;
    _updateHasChanges();
    setState(() {});
    _doFetchPage(preserveContent: true);
    showToast('已恢复快照，正在刷新页面数据...');
    AppLogger.i('EDITOR', 'restored snapshot: $snapshotId');
  }

  static String _typeLabel(String type) {
    switch (type) {
      case 'post':
        return '发帖';
      case 'comment':
        return '评论';
      case 'reply':
        return '回复';
      case 'editPost':
        return '编辑帖子';
      case 'editReply':
        return '编辑评论';
      default:
        return type;
    }
  }

  @override
  void dispose() {
    _titleCtl.removeListener(_onContentChanged);
    _contentCtl.removeListener(_onContentChanged);
    _titleCtl.dispose();
    _contentCtl.dispose();
    _contentFocusNode.dispose();
    _undoController.dispose();
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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isWide = MediaQuery.sizeOf(context).isWide;
    final settings = context.watch<SettingsProvider>();

    // 动态生成快捷键绑定：仅对可见且有关联快捷键的工具栏项注册
    final editorShortcuts = <ShortcutActivator, Intent>{};
    for (final item in settings.toolbarItems) {
      if (!item.visible) continue;
      final keyStr = settings.toolbarShortcut(item.id);
      if (keyStr.isEmpty) continue;
      final activator = ShortcutHelper.parse(keyStr);
      if (activator == null) continue;
      final action = resolveToolbarAction(item.id);
      if (action == null) continue;
      editorShortcuts[activator] = EditorToolbarIntent(action);
    }
    // 有未保存内容时拦截 Esc，先确认再退出
    if (_hasUnsavedChanges) {
      final esc = ShortcutHelper.parse('Escape');
      if (esc != null) editorShortcuts[esc] = EditorEscapeIntent();
    }
    // 拦截 Ctrl+V 以处理剪贴板图片
    editorShortcuts[SingleActivator(LogicalKeyboardKey.keyV, control: true)] =
        PasteIntent();

    return Shortcuts(
      shortcuts: editorShortcuts,
      child: Actions(
        actions: {
          EditorToolbarIntent: CallbackAction<EditorToolbarIntent>(
            onInvoke: (intent) {
              _handleToolbarAction(intent.action);
              return null;
            },
          ),
          EditorEscapeIntent: CallbackAction<EditorEscapeIntent>(
            onInvoke: (_) async {
              final ok = await _requestExit();
              if (ok && mounted) Navigator.of(context).pop();
              return null;
            },
          ),
          PasteIntent: CallbackAction<PasteIntent>(
            onInvoke: (_) async {
              await _handlePaste();
              return null;
            },
          ),
        },
        child: PopScope(
          canPop: !_hasUnsavedChanges,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final ok = await _requestExit();
            if (ok && mounted) Navigator.of(context).pop();
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(_pageTitle),
              surfaceTintColor: cs.surface,
              actions: [
                if (!isWide)
                  IconButton(
                    icon: Icon(_showPreview ? Icons.edit : Icons.visibility),
                    tooltip: _showPreview ? '编辑' : '预览',
                    onPressed: () =>
                        setState(() => _showPreview = !_showPreview),
                  ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  tooltip: '更多',
                  onSelected: (value) async {
                    switch (value) {
                      case 'save':
                        await _saveManualSnapshot();
                      case 'history':
                        _openHistoryPage();
                      case 'toolbar':
                        if (!context.mounted) return;
                        await context.push('/settings/editor');
                      case 'info':
                        if (!context.mounted) return;
                        final curTitle = _titleCtl.text.trim();
                        final curContent = _contentCtl.text.trim();
                        final fields = <String, dynamic>{
                          '类型': _pageTitle,
                          'URL': _pageData.fetchedUrl,
                          'formhash': _pageData.formhash,
                          'posttime': _pageData.posttime,
                          if (_pageData.fid.isNotEmpty) 'fid': _pageData.fid,
                          if (_pageData.tid.isNotEmpty) 'tid': _pageData.tid,
                          if (_pageData.pid.isNotEmpty) 'pid': _pageData.pid,
                          if (curTitle.isNotEmpty)
                            '标题': curTitle.length > 50
                                ? '${curTitle.substring(0, 50)}...'
                                : curTitle,
                          if (curContent.isNotEmpty)
                            '内容(前80字)': curContent.length > 80
                                ? '${curContent.substring(0, 80)}...'
                                : curContent,
                          if (_pageData.uploadHash.isNotEmpty)
                            'uploadHash': _pageData.uploadHash,
                          if (_imageList.isNotEmpty)
                            '图片': '${_imageList.length} 张',
                          if (_attachmentList.isNotEmpty)
                            '附件': '${_attachmentList.length} 个',
                        };
                        showPageInfoDialog(context, fields);
                      case 'refresh':
                        if (!_loadingPage) {
                          await _doFetchPage(preserveContent: false);
                        }
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'save',
                      child: ListTile(
                        leading: Icon(Icons.save_outlined, size: 20),
                        title: Text('手动保存'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'history',
                      child: ListTile(
                        leading: Icon(Icons.history, size: 20),
                        title: Text('编辑历史'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'toolbar',
                      child: ListTile(
                        leading: Icon(Icons.tune, size: 20),
                        title: Text('工具栏设置'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'info',
                      child: ListTile(
                        leading: Icon(Icons.info_outline, size: 20),
                        title: Text('页面信息'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'refresh',
                      child: ListTile(
                        leading: Icon(Icons.refresh_rounded, size: 20),
                        title: Text('刷新页面数据'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                _isSubmitting
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : TextButton.icon(
                        onPressed: _submit,
                        icon: const Icon(Icons.send_rounded, size: 18),
                        label: const Text('发布'),
                      ),
              ],
            ),
            body: _pageError != null
                ? PageErrorWidget(
                    message: _pageError!,
                    onRetry: () => _doFetchPage(),
                  )
                : isWide
                ? _buildWideLayout()
                : _buildNarrowLayout(),
          ),
        ),
      ),
    );
  }

  // ==================== 布局 ====================

  Widget _buildNarrowLayout() => IndexedStack(
    index: _showPreview ? 1 : 0,
    children: [_buildEditor(), _buildPreview()],
  );

  Widget _buildWideLayout() {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildEditor()),
        Container(width: 1, color: cs.outlineVariant),
        Expanded(child: _buildPreview()),
      ],
    );
  }

  Widget _buildEditor() {
    return Column(
      children: [
        _buildHintBar(),
        if (_isReply)
          QuotedPostCard(
            loading: _loadingQuoted,
            error: _quotedError,
            quotedPost: _quotedPost,
          ),
        if (_loadingPage)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('加载中...', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        if (_isPost)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              controller: _titleCtl,
              decoration: const InputDecoration(
                hintText: '标题',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              maxLines: 1,
              textInputAction: TextInputAction.next,
            ),
          ),
        ValueListenableBuilder<UndoHistoryValue>(
          valueListenable: _undoController,
          builder: (_, undoVal, __) {
            final s = context.read<SettingsProvider>();
            final items = s.toolbarItems;
            final shortcutsMap = {
              for (final item in items) item.id: s.toolbarShortcut(item.id),
            };
            return BBCodeToolbar(
              controller: _toolbarCtl,
              canUndo: undoVal.canUndo,
              canRedo: undoVal.canRedo,
              items: items,
              shortcuts: shortcutsMap,
            );
          },
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _contentCtl,
              focusNode: _contentFocusNode,
              undoController: _undoController,
              decoration: InputDecoration(
                hintText: _isPost
                    ? '想和大家分享点什么...'
                    : _isReply
                    ? '输入回复内容...'
                    : '输入评论内容...',
                border: const OutlineInputBorder(),
                isDense: true,
                alignLabelWithHint: true,
              ),
              maxLines: null,
              minLines: 1,
              expands: false,
              keyboardType: TextInputType.multiline,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreview() {
    return EditorPreview(
      data: _previewData,
      onShowRaw: (bbcode) => showRawBbcodeDialog(context, bbcode),
    );
  }
}
