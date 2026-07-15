import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/config/site_config.dart';

import 'package:mtbbs/core/emoji_loader.dart';
import 'package:mtbbs/core/page_fetcher.dart';
import 'package:mtbbs/core/logger.dart';
import 'package:mtbbs/api/forum/post/upload.dart' as upload_api;
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/core/shortcut_helper.dart';
import 'package:mtbbs/config/toolbar_config.dart';
import 'package:mtbbs/auth/providers/auth_provider.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/providers/history_provider.dart';
import 'package:mtbbs/models/browse_record.dart';
import 'package:mtbbs/models/editor_snapshot.dart';
import 'package:mtbbs/widgets/post_html_widget.dart';
import 'package:mtbbs/widgets/bbcode_controller.dart';
import 'package:mtbbs/widgets/bbcode_toolbar.dart';
import 'package:mtbbs/widgets/history_picker.dart';
import 'package:mtbbs/widgets/emoji_picker_sheet.dart';
import 'package:mtbbs/widgets/image_picker_sheet.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mtbbs/widgets/page_error_widget.dart';
import 'package:mtbbs/widgets/quoted_post_card.dart';
import 'package:mtbbs/providers/editor_history_provider.dart';
import 'package:mtbbs/pages/editor/editor_submit.dart';
import 'package:mtbbs/pages/editor/editor_dialogs.dart';
import 'package:mtbbs/pages/editor/editor_intents.dart';
import 'package:mtbbs/pages/editor/mt_image_sheet.dart';
import 'package:mtbbs/services/mt_image_hosting.dart';
import 'package:mtbbs/services/clipboard_paste.dart';

/// 编辑器类型
enum EditorType { post, comment, reply, editPost, editReply }

/// 统一编辑器页面
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

class _EditorPageState extends State<EditorPage> {
  // ==================== 核心控制器 ====================
  final _titleCtl = TextEditingController();
  final _contentCtl = BBCodeController();
  final _contentFocusNode = FocusNode();
  final _undoController = UndoHistoryController();
  Map<String, String> _emojiMap = {};
  bool _showPreview = false;
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

  /// 图片列表（编辑器生命周期内持久，供图片管理面板使用）
  List<Map<String, dynamic>> _imageList = [];
  final Set<String> _ignoredAids = <String>{};
  bool _loadingImages = false;

  /// 响应式数据（图片管理面板通过 ValueListenableBuilder 监听重建）
  final ValueNotifier<_ImageSheetData> _imageSheetDataNotifier = ValueNotifier(
    const _ImageSheetData([], false),
  );

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
            SiteConfig.current.forums[widget.fid] ?? '版块 ${widget.fid}';
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

    if (!result.success) {
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
      _aidToSrc = {
        for (final img in result.images)
          if (img['aid'] != null && img['src'] != null)
            img['aid']!: img['src']!,
      };
      _imageList = result.images.map((img) {
        return <String, dynamic>{
          'aid': img['aid'] ?? '',
          'src': img['src'] ?? '',
          'title': img['title'] ?? '',
          'type': 'existing',
        };
      }).toList();
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

    // 异步加载已上传但未绑定的图片
    _refreshImageList();
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
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已手动保存'), duration: Duration(seconds: 1)),
      );
    }
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

  // ==================== BBCode 预处理（预览用） ====================

  // ==================== 图片管理 ====================

  /// 同步图片数据到 notifier（让图片管理面板重建）
  void _syncImagesNotifier() {
    _imageSheetDataNotifier.value = _ImageSheetData(
      _imageList.where((i) => !_ignoredAids.contains(i['aid'])).toList(),
      _loadingImages,
    );
  }

  /// 刷新图片列表（合并页面已有 + 已上传未绑定的图片）
  Future<void> _refreshImageList() async {
    try {
      final fid = _pageData.fid.isNotEmpty ? _pageData.fid : widget.fid;
      final tid = _pageData.tid.isNotEmpty ? _pageData.tid : widget.tid;

      AppLogger.i('IMAGE', '刷新图片列表 fid=$fid tid=$tid');
      setState(() => _loadingImages = true);
      _syncImagesNotifier();
      final images = await upload_api.fetchUnusedImages(
        ApiService().dio,
        fid: fid,
        tid: tid.isNotEmpty ? tid : null,
      );
      if (!mounted) return;
      setState(() {
        for (final img in images) {
          final aid = img['aid']?.toString() ?? '';
          final src = img['src']?.toString() ?? '';
          if (aid.isEmpty || src.isEmpty) continue;
          // 合并到 _imageList（去重）
          if (!_imageList.any((i) => i['aid'] == aid)) {
            _imageList.add({
              'aid': aid,
              'src': src,
              'title': img['title']?.toString() ?? '',
              'type': 'uploaded',
            });
          }
          // 同时更新 _aidToSrc（供预览用）
          if (!_aidToSrc.containsKey(aid)) {
            _aidToSrc[aid] = src;
          }
        }
        _loadingImages = false;
      });
      _syncImagesNotifier();
    } catch (_) {
      if (mounted) {
        setState(() => _loadingImages = false);
        _syncImagesNotifier();
      }
    }
  }

  /// 处理图片上传（选择文件 → 上传 → 加入列表）
  Future<void> _handleImageUpload() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) return;
    if (_pageData.uploadHash.isEmpty) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty) return;
    final filePath = result.files.single.path;
    if (filePath == null) return;

    final file = File(filePath);
    try {
      final uploadResult = await upload_api.uploadImage(
        ApiService().dio,
        file: file,
        uid: auth.uid,
        uploadHash: _pageData.uploadHash,
      );
      if (!mounted) return;
      if (uploadResult['success'] == true) {
        final aid = uploadResult['aid']?.toString() ?? '';
        final src = uploadResult['src']?.toString() ?? '';
        final title = uploadResult['title']?.toString() ?? '';
        if (aid.isNotEmpty && src.isNotEmpty) {
          setState(() {
            _imageList.add({
              'aid': aid,
              'src': src,
              'title': title,
              'type': 'uploaded',
            });
            _aidToSrc[aid] = src;
          });
          _syncImagesNotifier();
        }
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('上传成功')));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('上传失败: ${uploadResult['error'] ?? '未知错误'}')),
          );
        }
      }
    } finally {
      // 清理 file_picker 产生的临时文件，避免残留
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
  }

  /// 删除图片（调用 API 删除 + 从本地列表移除）
  Future<void> _handleImageDelete(String aid) async {
    final ok = await upload_api.deleteUnusedImage(
      ApiService().dio,
      formhash: _pageData.formhash,
      tid: _pageData.tid.isNotEmpty ? _pageData.tid : widget.tid,
      pid: _pageData.pid.isNotEmpty ? _pageData.pid : widget.pid,
      aid: aid,
    );
    if (!mounted) return;
    if (ok) {
      setState(() {
        _imageList.removeWhere((i) => i['aid'] == aid);
        _aidToSrc.remove(aid);
      });
      _syncImagesNotifier();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已删除')));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('删除失败')));
    }
  }

  /// 忽略图片（从显示列表中隐藏）
  void _handleImageIgnore(String aid) {
    setState(() {
      _ignoredAids.add(aid);
      _imageList.removeWhere((i) => i['aid'] == aid);
      _aidToSrc.remove(aid);
    });
    _syncImagesNotifier();
  }

  /// 获取当前活跃的 AID 集合（未忽略的图片）
  Set<String> get _activeAids {
    return _imageList
        .map((i) => i['aid'] as String)
        .where((aid) => !_ignoredAids.contains(aid))
        .toSet();
  }

  /// 同步活跃 AID 到 BBCodeController
  void _syncPendingAids() {
    _contentCtl.pendingAids
      ..clear()
      ..addAll(_activeAids);
  }

  /// 预览前处理：将 [attachimg] 替换为 [img]
  String _preparePreviewBbcode(String bbcode) {
    return bbcode.replaceAllMapped(
      RegExp(r'\[attachimg\](\d+)\[/attachimg\]'),
      (m) {
        final aid = m.group(1) ?? '';
        final src = _aidToSrc[aid] ?? '';
        if (src.isNotEmpty) {
          final data = jsonEncode({
            'type': 'image_attach',
            'url': src,
            'aid': aid,
          });
          return '[appdata]$data[/appdata]';
        }
        return m.group(0)!;
      },
    );
  }

  // ==================== 工具栏操作 ====================

  void _handleToolbarAction(ToolbarAction action) {
    switch (action) {
      case ToolbarAction.undo:
        _undoController.undo();
        _focusContent();
      case ToolbarAction.redo:
        _undoController.redo();
        _focusContent();
      case ToolbarAction.bold:
        if (!_contentCtl.wrapSelection('[b]', '[/b]')) {
          showInlineInputDialog(
            context,
            '[b]',
            '[/b]',
            '加粗',
            '输入要加粗的文字',
            _contentCtl,
            _focusContent,
          );
        }
        _focusContent();
      case ToolbarAction.italic:
        if (!_contentCtl.wrapSelection('[i]', '[/i]')) {
          showInlineInputDialog(
            context,
            '[i]',
            '[/i]',
            '斜体',
            '输入要设置为斜体的文字',
            _contentCtl,
            _focusContent,
          );
        }
        _focusContent();
      case ToolbarAction.underline:
        if (!_contentCtl.wrapSelection('[u]', '[/u]')) {
          showInlineInputDialog(
            context,
            '[u]',
            '[/u]',
            '下划线',
            '输入要添加下划线的文字',
            _contentCtl,
            _focusContent,
          );
        }
        _focusContent();
      case ToolbarAction.strikethrough:
        if (!_contentCtl.wrapSelection('[s]', '[/s]')) {
          showInlineInputDialog(
            context,
            '[s]',
            '[/s]',
            '删除线',
            '输入要添加删除线的文字',
            _contentCtl,
            _focusContent,
          );
        }
        _focusContent();
      case ToolbarAction.quote:
        _contentCtl.wrapBlock('[quote]', '[/quote]');
        _focusContent();
      case ToolbarAction.code:
        _contentCtl.wrapBlock('[code]', '[/code]');
        _focusContent();
      case ToolbarAction.hr:
        _contentCtl.insertBlockTag('[hr]');
        _focusContent();
      case ToolbarAction.link:
        final sel = _contentCtl.selection;
        final selectedText = sel.isValid && !sel.isCollapsed
            ? _contentCtl.text.substring(sel.start, sel.end).trim()
            : '';
        if (selectedText.isNotEmpty) {
          final isUrl =
              selectedText.startsWith('http://') ||
              selectedText.startsWith('https://');
          if (isUrl) {
            _contentCtl.wrapSelection('[url]', '[/url]');
          } else {
            _contentCtl.wrapBlock('[url=]', '[/url]');
          }
          _focusContent();
        } else {
          showTextInputDialog(
            context,
            title: '插入链接',
            label: 'URL',
            hint: 'https://...',
            value: '',
            secondLabel: '显示文字',
            secondHint: '可选',
            secondValue: '',
            onSubmit: (url, text) {
              final hasUrl = url.isNotEmpty;
              final hasText = text.isNotEmpty;
              if (hasUrl && hasText) {
                _contentCtl.wrapInline('[url=$url]', '[/url]', text);
              } else if (hasUrl) {
                _contentCtl.wrapInline('[url]', '[/url]', url);
              } else if (hasText) {
                _contentCtl.wrapInline('[url=]', '[/url]', text);
              }
              if (hasUrl || hasText) _focusContent();
            },
          );
        }
      case ToolbarAction.image:
        _showImagePickerSheet();
      case ToolbarAction.imageLongPress:
        showTextInputDialog(
          context,
          title: '插入图片',
          label: '图片 URL',
          hint: 'https://...',
          value: '',
          onSubmit: (url, _) {
            if (url.isNotEmpty) {
              _contentCtl.insertImage(url);
              _focusContent();
            }
          },
        );
      case ToolbarAction.emoji:
        final emojiService = EmojiService();
        if (!emojiService.isLoaded) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('暂无表情数据，请在设置中加载')));
          return;
        }
        _showEmojiPickerSheet(emojiService.groups);
      case ToolbarAction.color:
        showColorPickerDialog(
          context,
          _contentCtl,
          _focusContent,
          isBackcolor: false,
        );
      case ToolbarAction.backcolor:
        showColorPickerDialog(
          context,
          _contentCtl,
          _focusContent,
          isBackcolor: true,
        );
      case ToolbarAction.alignLeft:
        _contentCtl.wrapParam('align', 'left', '[/align]');
        _focusContent();
      case ToolbarAction.alignCenter:
        _contentCtl.wrapParam('align', 'center', '[/align]');
        _focusContent();
      case ToolbarAction.alignRight:
        _contentCtl.wrapParam('align', 'right', '[/align]');
        _focusContent();
      case ToolbarAction.listUl:
        _contentCtl.wrapParam('list', '', '[/list]');
        _focusContent();
      case ToolbarAction.listOl:
        _contentCtl.wrapParam('list', '1', '[/list]');
        _focusContent();
      case ToolbarAction.select:
        _contentCtl.selectTag();
        _focusContent();
      case ToolbarAction.fontSize:
        showFontSizePicker(context, _contentCtl, _focusContent);
      case ToolbarAction.history:
        _showHistoryDialog();
      case ToolbarAction.mtImage:
        _showMtImageDialog();
      case ToolbarAction.clearStyles:
        _contentCtl.clearStyles();
        _focusContent();
    }
  }

  void _focusContent() => _contentFocusNode.requestFocus();

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

  /// 处理 Ctrl+V 粘贴：剪贴板图片 → 默认上传，文本 → 插入编辑器
  Future<void> _handlePaste() async {
    // 尝试剪贴板图片
    final imgFile = await ClipboardPasteService.pasteImage();
    if (imgFile != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('正在上传剪贴板图片…'),
          duration: Duration(seconds: 1),
        ),
      );
      await _uploadDefaultImage(imgFile);
      await imgFile.delete();
      return;
    }

    // 回退到文本粘贴
    final text = await ClipboardPasteService.pasteText();
    if (text != null && mounted) {
      final sel = _contentCtl.selection;
      final pos = sel.isValid ? sel.start : _contentCtl.text.length;
      _contentCtl.value = TextEditingValue(
        text: _contentCtl.text.replaceRange(pos, pos, text),
        selection: TextSelection.collapsed(offset: pos + text.length),
      );
    }
  }

  /// 上传图片到论坛（默认上传），成功后插入 [attachimg]
  Future<void> _uploadDefaultImage(File file) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn || _pageData.uploadHash.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('未登录或无上传权限')));
      }
      return;
    }

    try {
      final uploadResult = await upload_api.uploadImage(
        ApiService().dio,
        file: file,
        uid: auth.uid,
        uploadHash: _pageData.uploadHash,
      );
      if (!mounted) return;
      if (uploadResult['success'] == true) {
        final aid = uploadResult['aid']?.toString() ?? '';
        final src = uploadResult['src']?.toString() ?? '';
        final title = uploadResult['title']?.toString() ?? '';
        if (aid.isNotEmpty && src.isNotEmpty) {
          setState(() {
            _imageList.add({
              'aid': aid,
              'src': src,
              'title': title,
              'type': 'uploaded',
            });
            _aidToSrc[aid] = src;
          });
          _syncImagesNotifier();
          _contentCtl.wrapInline('', '', '[attachimg]$aid[/attachimg]');
          _focusContent();
        }
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('剪贴板图片已上传')));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('上传失败: ${uploadResult['error'] ?? '未知错误'}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('上传失败: $e')));
      }
    }
  }

  void _showHistoryDialog() {
    final history = context.read<HistoryProvider>();
    if (history.totalCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无浏览记录'), duration: Duration(seconds: 1)),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 480),
        titlePadding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
        contentPadding: EdgeInsets.zero,
        title: Row(
          children: [
            const Expanded(
              child: Text(
                '插入历史记录',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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
        content: SizedBox(
          width: 420,
          height: 400,
          child: HistoryPicker(
            onPick: (record) {
              Navigator.of(ctx).pop();
              _insertHistoryRecord(record);
            },
          ),
        ),
      ),
    );
  }

  /// MT 图床上传 + 历史弹窗
  void _showMtImageDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => MtImageSheet(
        hosting: _mtImageHosting,
        onInsert: (bbcode) {
          _contentCtl.wrapInline('', '', ' $bbcode ');
          _focusContent();
        },
      ),
    );
  }

  void _insertHistoryRecord(BrowseRecord record) {
    final settings = context.read<SettingsProvider>();
    final format = record.type == 'thread'
        ? settings.historyFormatThread
        : settings.historyFormatUser;
    final url = record.info['url']?.toString() ?? '';
    final text = format.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) {
      final key = m.group(1)!;
      return record.info[key]?.toString() ?? m.group(0)!;
    });
    _contentCtl.insertLink(url, text: text);
    _focusContent();
  }

  void _showEmojiPickerSheet(List<Map<String, dynamic>> groups) {
    final frequentEmojis = EmojiService().frequentlyUsed;
    showModalBottomSheet(
      context: context,
      constraints: const BoxConstraints(maxWidth: 500, maxHeight: 420),
      builder: (ctx) => EmojiPickerSheet(
        groups: groups,
        frequentEmojis: frequentEmojis,
        onEmojiPicked: (emoji) {
          final insertText = emoji['insertText'] as String;
          final smilieId = emoji['smilieId'] as String;
          _contentCtl.wrapInline('', '', insertText);
          EmojiService().recordUsage(smilieId);
          _focusContent();
        },
      ),
    );
  }

  void _showImagePickerSheet() {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先登录')));
      return;
    }
    if (_pageData.uploadHash.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('页面数据未加载，无法上传')));
      return;
    }
    // 同步活跃 AID
    _syncPendingAids();

    showModalBottomSheet(
      context: context,
      constraints: const BoxConstraints(maxWidth: 500, maxHeight: 450),
      builder: (ctx) => ValueListenableBuilder<_ImageSheetData>(
        valueListenable: _imageSheetDataNotifier,
        builder: (_, data, __) => ImagePickerSheet(
          images: data.images,
          loading: data.loading,
          ignoredAids: _ignoredAids,
          contentText: _contentCtl.text,
          controller: _contentCtl,
          onUpload: _handleImageUpload,
          onDelete: _handleImageDelete,
          onIgnore: _handleImageIgnore,
          onRefresh: _refreshImageList,
          onInsert: (aid) {
            _contentCtl.wrapInline('', '', '[attachimg]$aid[/attachimg]');
            _syncPendingAids();
          },
        ),
      ),
    ).then((_) {
      _syncPendingAids();
      if (mounted) _refreshImageList();
    });
  }

  // ==================== 提交 ====================

  Future<void> _submit() async {
    final title = _titleCtl.text.trim();
    final content = _contentCtl.text.trim();
    if (content.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请输入内容')));
      }
      return;
    }
    if (widget.type == EditorType.post && title.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请输入标题')));
      }
      return;
    }
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请先登录')));
      }
      return;
    }
    if (_isEdit &&
        (!_pageData.formhash.isNotEmpty || !_pageData.posttime.isNotEmpty)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('页面数据未加载，请稍后')));
      }
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final result = await _submitHelper.submit(_pageData, title, content);
      if (!mounted) return;
      if (result.success) {
        final msg = result.needsApproval ? '需要审核' : '操作成功';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
        _isLeavingNormally = true;
        _autoSaveTimer?.cancel();
        context.read<EditorHistoryProvider>().markSubmitted(_sessionKey);
        Navigator.of(context).pop({'success': true, 'result': result});
      } else {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('操作失败: ${result.message}')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('网络错误: $e')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('快照不存在')));
      return;
    }
    _saveManualSnapshot();
    _titleCtl.text = snapshot.title;
    _contentCtl.text = snapshot.content;
    _contentCtl.pendingAids = snapshot.pendingAids.toSet();
    _pageData = snapshot.pageData.toPageFormData();
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已恢复快照，正在刷新页面数据...'),
        duration: Duration(seconds: 2),
      ),
    );
    AppLogger.i('EDITOR', 'restored snapshot: $snapshotId');
  }

  // ==================== 提示系统 ====================

  /// 添加顶栏提示（自动去重）
  void _addHint(String id, String message) {
    if (_dismissedHints.contains(id)) return;
    // 通过 key 强制重建 HintBar widget
    setState(() {});
  }

  /// 关闭指定提示
  void _dismissHint(String id) {
    _dismissedHints.add(id);
    setState(() {});
  }

  /// 检测内容是否包含不兼容的 Emoji（4 字节 UTF-8 字符）
  bool _checkIncompatibleEmoji(String text) {
    for (final rune in text.runes) {
      if (rune > 0xFFFF) return true;
    }
    return false;
  }

  /// 更新 Emoji 警告提示状态
  void _updateEmojiWarning() {
    final hasEmoji =
        _checkIncompatibleEmoji(_titleCtl.text) ||
        _checkIncompatibleEmoji(_contentCtl.text);
    if (hasEmoji != _hasEmojiWarning) {
      setState(() => _hasEmojiWarning = hasEmoji);
      if (hasEmoji) {
        _dismissedHints.remove('emoji'); // 重新出现时重新显示
      }
    }
  }

  /// 构建顶栏提示条
  Widget _buildHintBar() {
    final hints = <Widget>[];

    // Emoji 警告
    if (_hasEmojiWarning && !_dismissedHints.contains('emoji')) {
      hints.add(
        _hintItem(
          id: 'emoji',
          icon: Icons.warning_amber_rounded,
          color: Colors.orange,
          message: '输入内容包含不兼容的 Emoji，提交后可能被截断',
        ),
      );
    }

    // 意外关闭
    if (!_dismissedHints.contains('unexpected_close')) {
      final historyProv = context.read<EditorHistoryProvider>();
      if (historyProv.hasSession(_sessionKey)) {
        hints.add(
          _hintItem(
            id: 'unexpected_close',
            icon: Icons.info_outline,
            color: Colors.blue,
            message: '上次编辑器意外关闭，可在编辑历史中恢复',
          ),
        );
      }
    }

    if (hints.isEmpty) return const SizedBox.shrink();
    return Container(
      color: Colors.amber.shade50,
      child: Column(mainAxisSize: MainAxisSize.min, children: hints),
    );
  }

  Widget _hintItem({
    required String id,
    required IconData icon,
    required Color color,
    required String message,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.amber.shade100)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
            ),
          ),
          GestureDetector(
            onTap: () => _dismissHint(id),
            child: Container(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close, size: 14, color: Colors.grey.shade400),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _titleCtl.removeListener(_onContentChanged);
    _contentCtl.removeListener(_onContentChanged);
    _titleCtl.dispose();
    _contentCtl.dispose();
    _contentFocusNode.dispose();
    _undoController.dispose();
    _autoSaveTimer?.cancel();
    if (!_isLeavingNormally && _hasUnsavedChanges) {
      try {
        _saveAutoSnapshot();
      } catch (_) {}
    }
    super.dispose();
  }

  // ==================== Build ====================

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 600;
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
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
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
                      case 'info':
                        if (!context.mounted) return;
                        final fields = <String, dynamic>{
                          'URL': _pageData.fetchedUrl,
                          'formhash': _pageData.formhash,
                          'posttime': _pageData.posttime,
                          if (_pageData.fid.isNotEmpty) 'fid': _pageData.fid,
                          if (_pageData.tid.isNotEmpty) 'tid': _pageData.tid,
                          if (_pageData.pid.isNotEmpty) 'pid': _pageData.pid,
                          if (_pageData.noticeauthor.isNotEmpty)
                            'noticeauthor': _pageData.noticeauthor,
                          if (_pageData.reppid.isNotEmpty)
                            'reppid': _pageData.reppid,
                          if (_pageData.title.isNotEmpty) '标题': _pageData.title,
                          if (_pageData.content.isNotEmpty)
                            '内容(前80字)': _pageData.content.length > 80
                                ? '${_pageData.content.substring(0, 80)}...'
                                : _pageData.content,
                          if (_pageData.images.isNotEmpty)
                            '图片数': '${_pageData.images.length} 张',
                          if (_pageData.uploadHash.isNotEmpty)
                            'uploadHash': _pageData.uploadHash,
                          if (_imageList.isNotEmpty)
                            '图片列表(JSON)': const JsonEncoder.withIndent(
                              '  ',
                            ).convert(_imageList),
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

  Widget _buildNarrowLayout() =>
      _showPreview ? _buildPreview() : _buildEditor();

  Widget _buildWideLayout() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: _buildEditor()),
      Container(width: 1, color: Colors.grey.shade300),
      Expanded(child: _buildPreview()),
    ],
  );

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
    final title = _titleCtl.text.trim();
    final content = _contentCtl.text.trim();
    if (title.isEmpty && content.isEmpty) {
      return Center(
        child: Text('输入内容后即可预览', style: TextStyle(color: Colors.grey.shade400)),
      );
    }
    final settings = context.read<SettingsProvider>();
    final previewBbcode = _preparePreviewBbcode(content);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ),
          content.isNotEmpty
              ? GestureDetector(
                  onLongPress: () =>
                      _showRawBbcodeDialog(context, previewBbcode),
                  child: PostHtmlWidget(
                    bbcode: previewBbcode,
                    emojiMap: _emojiMap,
                    smilieIdMap: EmojiService().smilieIdMap,
                    disabledTags: settings.disabledBbcodeTags,
                    autoDetectUrls: settings.autoDetectUrls,
                  ),
                )
              : Text('暂无内容', style: TextStyle(color: Colors.grey.shade400)),
        ],
      ),
    );
  }

  void _showRawBbcodeDialog(BuildContext context, String bbcode) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.code, size: 18),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('预览 BBCode', style: TextStyle(fontSize: 16)),
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
          child: SelectableText(
            bbcode,
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              height: 1.5,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: bbcode));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已复制'),
                  duration: Duration(seconds: 1),
                ),
              );
              Navigator.of(ctx).pop();
            },
            child: const Text('复制'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
