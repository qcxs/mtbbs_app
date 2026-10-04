part of 'editor_page.dart';

/// 工具栏动作分发与剪贴板粘贴。
extension on _EditorPageState {
  /// 处理工具栏项点击 / 快捷键
  ///
  /// - 模板项（带 `template`）：按 `${selectText}` 应用文本模板
  /// - 复杂项：转交 [_handleToolbarAction]（弹窗/面板/上传）
  void _handleToolbarItem(String id) {
    if (id == kImageLongPressId) {
      _handleToolbarAction(ToolbarAction.imageLongPress);
      return;
    }
    // 末尾固定追加的「设置」按钮：进编辑器设置页
    if (id == kEditorSettingsId) {
      context.push('/settings/editor');
      return;
    }

    final items = context.read<SettingsProvider>().toolbarItems;
    final index = items.indexWhere((e) => e.id == id);
    if (index >= 0) {
      final item = items[index];
      final template = toolbarTemplateOf(item);
      if (template != null) {
        // 无占位符的块级模板（[hr]、表格骨架）按块级插入；其余走统一模板应用
        if (toolbarIsBlockOf(item) && !template.contains(kSelectTextToken)) {
          _contentCtl.insertBlockTag(template);
        } else {
          _contentCtl.applyTemplate(template);
        }
        _focusContent();
        return;
      }
    }

    final action = resolveToolbarAction(id);
    if (action != null) _handleToolbarAction(action);
  }

  /// 处理复杂工具栏动作（需要弹窗 / 选择面板 / 上传的项）
  void _handleToolbarAction(ToolbarAction action) {
    switch (action) {
      case ToolbarAction.undo:
        _undoController.undo();
        _focusContent();
      case ToolbarAction.redo:
        _undoController.redo();
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
      case ToolbarAction.attach:
        _showAttachmentPickerSheet();
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
          showToast('暂无表情数据，请在设置中加载');
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
      case ToolbarAction.select:
        _contentCtl.selectTag();
        _focusContent();
      case ToolbarAction.fontSize:
        showFontSizePicker(context, _contentCtl, _focusContent);
      case ToolbarAction.history:
        _showHistoryDialog();
      case ToolbarAction.editHistory:
        _openHistoryPage();
      case ToolbarAction.mdImport:
        _openMdImportSheet();
      case ToolbarAction.mtImage:
        _showMtImageDialog();
      case ToolbarAction.clearStyles:
        _contentCtl.clearStyles();
        _focusContent();
    }
  }

  /// 处理 Ctrl+V 粘贴：剪贴板图片 → 默认上传，文本 → 插入编辑器
  Future<void> _handlePaste() async {
    // 尝试剪贴板图片
    final imgFile = await ClipboardPasteService.pasteImage();
    if (imgFile != null && mounted) {
      showToast('正在上传剪贴板图片…');
      await _uploadDefaultImage(imgFile);
      await imgFile.delete();
      return;
    }

    // 回退到文本粘贴
    final text = await ClipboardHelper.read();
    if (text != null && mounted) {
      final sel = _contentCtl.selection;
      final pos = sel.isValid ? sel.start : _contentCtl.text.length;
      _contentCtl.value = TextEditingValue(
        text: _contentCtl.text.replaceRange(pos, pos, text),
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
      editorHasContent: _contentCtl.text.trim().isNotEmpty,
    );
    if (result == null || !mounted) return;

    if (result.mode == MdImportMode.replace) {
      _contentCtl.value = TextEditingValue(
        text: result.bbcode,
        selection: TextSelection.collapsed(offset: result.bbcode.length),
      );
      showToast('已替换正文');
    } else {
      final sel = _contentCtl.selection;
      final pos = sel.isValid ? sel.start : _contentCtl.text.length;
      _contentCtl.value = TextEditingValue(
        text: _contentCtl.text.replaceRange(pos, pos, result.bbcode),
        selection: TextSelection.collapsed(offset: pos + result.bbcode.length),
      );
      showToast('已插入到光标处');
    }
    _focusContent();
  }
}
