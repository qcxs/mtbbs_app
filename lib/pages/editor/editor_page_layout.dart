part of 'editor_page.dart';

/// 页面布局构建 — 整体骨架、宽/窄屏布局、编辑区与预览区。
extension on _EditorPageState {
  /// 「图片」「附件」角标＝当前已上传的数量；有角标时该项强制显示
  /// （即使被用户在工具栏设置里隐藏）。工具栏渲染与快捷键注册共用同一判定。
  Map<String, int> get _editorBadges => {
    if (_images.list.isNotEmpty) 'image': _images.list.length,
    if (_attachmentList.isNotEmpty) 'attach': _attachmentList.length,
  };

  Widget _buildPage(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isWide = MediaQuery.sizeOf(context).isWide;
    final settings = context.watch<SettingsProvider>();

    // 「图片」「附件」角标＝当前已上传的数量；有角标时该项强制显示
    // （即使被用户在工具栏设置里隐藏）。工具栏渲染与下方快捷键注册共用。
    final badges = _editorBadges;

    // 动态生成快捷键绑定：默认对**所有**有快捷键的工具栏项注册。
    //
    // 默认不看 item.visible：按钮显隐管的是"界面清爽"，快捷键管的是
    // "能力是否可用"，两者解耦后隐藏按钮不会连带废掉快捷键
    // （列表/表格默认不显示按钮，但 Ctrl+Shift+] / Ctrl+T 仍应生效）。
    // 用户可在「设置 → 编辑与快捷键 → 隐藏项快捷键可用」关闭此行为，
    // 关闭后隐藏项（且非角标强制显示）的快捷键不再注册。
    // 真要停用某个键，把它的快捷键清空即可。
    final shortcutWhenHidden = settings.toolbarShortcutWhenHidden;
    final editorShortcuts = <ShortcutActivator, Intent>{};
    for (final item in settings.toolbarItems) {
      final keyStr = settings.toolbarShortcut(item.id);
      if (keyStr.isEmpty) continue;
      if (!shortcutWhenHidden && !toolbarItemShown(item, badges)) continue;
      final activator = ShortcutHelper.parse(keyStr);
      if (activator == null) continue;
      editorShortcuts[activator] = EditorToolbarIntent(item.id);
    }
    // 有未保存内容时拦截 Esc，先确认再退出；图片侧栏打开时 Esc 优先关侧栏
    if (_hasUnsavedChanges || _showImagePanel) {
      final esc = ShortcutHelper.parse('Escape');
      if (esc != null) editorShortcuts[esc] = EditorEscapeIntent();
    }
    // 注意：Ctrl+V 刻意**不在这里注册**。它只服务正文（剪贴板图片→上传），
    // 注册在正文输入框上；若放到页面级，标题等其它输入框的祖先链里也有它，
    // Ctrl+V 会被截走并统一写进正文（见 _buildEditor 内正文的 Shortcuts）。

    return Shortcuts(
      shortcuts: editorShortcuts,
      child: Actions(
        actions: {
          EditorToolbarIntent: CallbackAction<EditorToolbarIntent>(
            onInvoke: (intent) {
              _handleToolbarItem(intent.id);
              return null;
            },
          ),
          EditorEscapeIntent: CallbackAction<EditorEscapeIntent>(
            onInvoke: (_) async {
              // Esc 先关图片侧栏（仅宽屏时存在），再走退出确认
              if (_showImagePanel && MediaQuery.sizeOf(context).isWide) {
                _setState(() => _showImagePanel = false);
                return null;
              }
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
                        final curTitle = _session.titleCtl.text.trim();
                        final curContent = _session.contentCtl.text.trim();
                        final fields = <String, dynamic>{
                          '类型': _pageTitle,
                          'URL': _session.pageData.fetchedUrl,
                          'formhash': _session.pageData.formhash,
                          'posttime': _session.pageData.posttime,
                          if (_session.pageData.fid.isNotEmpty)
                            'fid': _session.pageData.fid,
                          if (_session.pageData.tid.isNotEmpty)
                            'tid': _session.pageData.tid,
                          if (_session.pageData.pid.isNotEmpty)
                            'pid': _session.pageData.pid,
                          if (curTitle.isNotEmpty)
                            '标题': curTitle.length > 50
                                ? '${curTitle.substring(0, 50)}...'
                                : curTitle,
                          if (curContent.isNotEmpty)
                            '内容(前80字)': curContent.length > 80
                                ? '${curContent.substring(0, 80)}...'
                                : curContent,
                          if (_session.pageData.uploadHash.isNotEmpty)
                            'uploadHash': _session.pageData.uploadHash,
                          if (_images.list.isNotEmpty)
                            '图片': '${_images.list.length} 张',
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
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 侧栏占预览区右侧约一半，限制在 240~320，
              // 保证左侧预览仍可见、可滚动
              final panelWidth = (constraints.maxWidth * 0.55)
                  .clamp(240.0, 320.0)
                  .toDouble();
              return Stack(
                children: [
                  Positioned.fill(child: _buildPreview()),
                  if (_showImagePanel)
                    Positioned(
                      top: 0,
                      right: 0,
                      bottom: 0,
                      width: panelWidth,
                      child: _buildWideImagePanel(),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// 宽屏图片侧栏：覆盖在预览区右侧，无遮罩，可连续插入
  Widget _buildWideImagePanel() {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      elevation: 8,
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: cs.outlineVariant)),
        ),
        child: ListenableBuilder(
          listenable: _images,
          builder: (_, __) => ImagePickerSheet(
            embedded: true,
            images: _images.list,
            loading: _images.loading,
            ignoredAids: _images.ignoredAids,
            contentText: _session.contentCtl.text,
            controller: _session.contentCtl,
            onUpload: _images.upload,
            onDelete: _images.delete,
            onIgnore: _images.ignore,
            onRefresh: _images.refresh,
            onInsert: (aid) {
              _session.contentCtl.wrapInline(
                '',
                '',
                '[attachimg]$aid[/attachimg]',
              );
              _images.syncPendingAids();
              _focusContent();
            },
            onClose: () => _setState(() => _showImagePanel = false),
            allowedExtensions: _session.pageData.imageExtensions.isNotEmpty
                ? _session.pageData.imageExtensions
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildEditor() {
    _syncGutterMeasureWithWidth(context);
    return Column(
      children: [
        _buildHintBar(),
        if (_isReply)
          QuotedPostCard(
            loading: _loadingQuoted,
            error: _quotedError,
            quotedPost: _session.quotedPost,
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
              controller: _session.titleCtl,
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
            return KeyedSubtree(
              key: _toolbarKey,
              child: BBCodeToolbar(
                controller: _toolbarCtl,
                canUndo: undoVal.canUndo,
                canRedo: undoVal.canRedo,
                items: items,
                shortcuts: shortcutsMap,
                badges: _editorBadges,
              ),
            );
          },
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: _editorScrollCtl,
            padding: const EdgeInsets.fromLTRB(6, 12, 12, 12),
            child: Stack(
              children: [
                // 正文用内边距给标记槽让位。
                // 不让标记槽用负偏移落进外边距：越界的子树能画出来但**点不到**
                // （RenderBox.hitTest 先判 size.contains）。
                Padding(
                  padding: const EdgeInsets.only(left: kMarkerGutterWidth),
                  // SizedBox 撑满宽度：Stack 的 loose 约束下 TextField 否则会缩到内容宽
                  child: SizedBox(
                    width: double.infinity,
                    // Ctrl+V 只在这一层拦截：正文需要"剪贴板图片 → 上传"，
                    // 且正文的文本粘贴在 _handlePaste 里统一处理。
                    // 放在页面级会让标题等输入框也被截走、粘贴写进正文；
                    // 收在这里，其它输入框就沿用框架默认的粘贴行为。
                    child: Shortcuts(
                      shortcuts: {
                        SingleActivator(LogicalKeyboardKey.keyV, control: true):
                            PasteIntent(),
                      },
                      child: TextField(
                        key: _editorContentKey,
                        controller: _session.contentCtl,
                        focusNode: _contentFocusNode,
                        undoController: _undoController,
                        // 选中第一行时选择菜单会压住上方工具栏 → 自动翻到选区下方
                        contextMenuBuilder: (context, editableTextState) =>
                            buildEditorSelectionToolbar(
                              editableTextState: editableTextState,
                              toolbarKey: _toolbarKey,
                            ),
                        maxLength: context
                            .read<SettingsProvider>()
                            .postMaxLength,
                        // 隐藏 "0/65535" 计数器：上限仅作约束，不做展示
                        buildCounter:
                            (
                              _, {
                              required currentLength,
                              required isFocused,
                              maxLength,
                            }) => null,
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
                ),
                // 标记槽：与编辑框同一个 Stack（同一坐标系），当前锚点显示箭头
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: BlockMarkerGutter(
                    marks: _editorMarks,
                    activeId: _activeAnchor,
                    onTapId: _onEditorGutterTap,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreview() {
    return EditorPreview(
      key: _previewKey,
      data: _previewData,
      activeAnchor: _activeAnchor,
      onTapAnchor: _onPreviewGutterTap,
      onShowRaw: () => showRawBbcodeDialog(context, _session.contentCtl.text),
    );
  }
}
