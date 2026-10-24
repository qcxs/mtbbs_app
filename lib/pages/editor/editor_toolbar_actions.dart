part of 'editor_page.dart';

/// 工具栏动作分发与剪贴板粘贴。
extension on _EditorPageState {
  /// 上下文相关入口的回调（完整版形态）。动作逻辑本体在
  /// [dispatchToolbarItem]（`editor_interactions.dart`），与迷你版共用。
  EditorActionHooks get _actionHooks => EditorActionHooks(
    focus: _focusContent,
    onImage: _showImagePickerSheet,
    onAttachment: _showAttachmentPickerSheet,
    onMtImage: _showMtImageDialog,
    onHistory: _showHistoryDialog,
    onHistoryPage: _openHistoryPage,
    onMdImport: _openMdImportSheet,
    onQuickReply: () =>
        showQuickReplyPicker(context, _session.contentCtl, _focusContent),
    onOpenSettings: () => context.push('/settings/editor'),
    undoController: _undoController,
  );

  /// 处理工具栏项点击 / 快捷键（分发见 [dispatchToolbarItem]）
  void _handleToolbarItem(String id) {
    dispatchToolbarItem(
      context,
      _session.contentCtl,
      context.read<SettingsProvider>().toolbarItems,
      id: id,
      hooks: _actionHooks,
    );
  }

  /// 处理 Ctrl+V 粘贴：
  /// - 资源管理器复制的文件（可多选）→ 图片走图片上传，其余走附件上传
  /// - 截图 / 浏览器复制图片 → 默认上传
  /// - 纯文本 → 插入编辑器
  Future<void> _handlePaste() async {
    // 一次 PowerShell 调用同时检测文件列表与图片
    final clip = await ClipboardPasteService.pasteClipboard();

    // 1. 资源管理器复制的文件（CF_HDROP，可多选）
    if (clip.files.isNotEmpty) {
      if (mounted) {
        showToast('正在上传剪贴板文件…');
        await _uploadPastedFiles(clip.files);
      }
      // 缓存副本用完即删（不会碰用户原文件）
      for (final f in clip.files) {
        try {
          await f.delete();
        } catch (_) {}
      }
      return;
    }

    // 2. 剪贴板图片（截图 / 浏览器复制）
    final imgFile = clip.image;
    if (imgFile != null && mounted) {
      showToast('正在上传剪贴板图片…');
      await _uploadDefaultImage(imgFile);
      await imgFile.delete();
      return;
    }

    // 只复制了文件夹等无法直接上传的内容 → 明确提示（否则看起来像"粘贴没反应"）
    if (clip.ignored > 0) {
      if (mounted) showToast('暂不支持粘贴文件夹');
      return;
    }

    // 回退到文本粘贴
    final text = await ClipboardHelper.read();
    if (text != null && mounted) {
      final sel = _session.contentCtl.selection;
      final pos = sel.isValid ? sel.start : _session.contentCtl.text.length;
      _session.contentCtl.value = TextEditingValue(
        text: _session.contentCtl.text.replaceRange(pos, pos, text),
        selection: TextSelection.collapsed(offset: pos + text.length),
      );
    }
  }

  /// 打开「导入 Markdown」底部面板，并把转换结果写入正文。
  ///
  /// 面板只做 Markdown → BBCode 的编辑与预览，写入动作在这里完成：
  /// 通过 `controller.value` 一次性替换/插入，由 Flutter 的 UndoHistory
  /// 自动入栈（见 docs/07 #8），因此整次导入可一步撤销。
  Future<void> _openMdImportSheet() async {
    final result = await showMdImportSheet(
      context,
      editorHasContent: _session.contentCtl.text.trim().isNotEmpty,
    );
    if (result == null || !mounted) return;

    if (result.mode == MdImportMode.replace) {
      _session.contentCtl.value = TextEditingValue(
        text: result.bbcode,
        selection: TextSelection.collapsed(offset: result.bbcode.length),
      );
      showToast('已替换正文');
    } else {
      final sel = _session.contentCtl.selection;
      final pos = sel.isValid ? sel.start : _session.contentCtl.text.length;
      _session.contentCtl.value = TextEditingValue(
        text: _session.contentCtl.text.replaceRange(pos, pos, result.bbcode),
        selection: TextSelection.collapsed(offset: pos + result.bbcode.length),
      );
      showToast('已插入到光标处');
    }
    _focusContent();
  }
}
