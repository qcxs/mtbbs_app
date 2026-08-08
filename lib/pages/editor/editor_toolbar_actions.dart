part of 'editor_page.dart';

/// 工具栏动作分发与剪贴板粘贴。
extension on _EditorPageState {
  /// 处理工具栏动作（BBCode 包裹/弹窗/选择面板）
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
      case ToolbarAction.hide:
        _contentCtl.wrapBlock('[hide]', '[/hide]');
        _focusContent();
      case ToolbarAction.free:
        _contentCtl.wrapBlock('[free]', '[/free]');
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
}
