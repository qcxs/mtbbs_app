part of 'editor_page.dart';

/// 页面布局构建 — 整体骨架、宽/窄屏布局、编辑区与预览区。
extension on _EditorPageState {
  Widget _buildPage(BuildContext context) {
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
                        _setState(() => _showPreview = !_showPreview),
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
                      case 'markdown':
                        await _openMdImportSheet();
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
                      value: 'markdown',
                      child: ListTile(
                        leading: Icon(Icons.article_outlined, size: 20),
                        title: Text('导入 Markdown'),
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
