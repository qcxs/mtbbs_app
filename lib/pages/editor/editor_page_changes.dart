part of 'editor_page.dart';

/// 变更跟踪与自动保存 — 内容监听、脏状态计算、预览防抖与快照落盘。
extension on _EditorPageState {
  void _onContentChanged() {
    _setState(() {});
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
      final selection = _contentCtl.selection;
      final color = _previewHighlightColor();
      // 预览与编辑区**共用同一份锚点表**：第 i 个块就是第 i 个锚点。
      // 这里只负责把每个锚点自己的源码切片加工成"渲染用的 BBCode"：
      //   1. 选区落在本锚点内的部分 → [backcolor] 包裹（偏移是切片内的，
      //      所以选区跨锚点时各块各取交集，不需要做全局偏移换算）
      //   2. [attachimg]/[attach] → [appdata]（页面自己的资源映射）
      // 两步都只作用于**切片内部**，因此不可能改变锚点结构。
      final blocks = <EditorPreviewBlock>[
        for (final a in _anchors)
          EditorPreviewBlock(
            _preparePreviewBbcode(_highlightInAnchor(a, selection, color)),
            a.label,
          ),
      ];
      final newData = EditorPreviewData(title, blocks);
      if (_previewData.value != newData) _previewData.value = newData;
    });
  }

  /// 选区落在 [a] 区间内的部分用 `[backcolor]` 包起来。
  ///
  /// 偏移换算在切片内完成（`- a.start`），所以编辑器里选中跨段的文字也能逐段
  /// 高亮，且不依赖任何全局偏移补偿。
  String _highlightInAnchor(BbAnchor a, TextSelection selection, String color) {
    if (!selection.isValid || selection.isCollapsed) return a.raw;
    final from = selection.start.clamp(a.start, a.end) - a.start;
    final to = selection.end.clamp(a.start, a.end) - a.start;
    if (from >= to) return a.raw;
    return bbcodeHighlightSelection(a.raw, from, to, color);
  }

  /// 预览高亮色：主题色与背景**混成不透明色**。
  ///
  /// 刻意不用 8 位带 alpha 的 hex（`#RRGGBBAA`）：渲染层的 CSS 颜色解析
  /// 不一定认，混成不透明色在任何情况下都能解析。
  String _previewHighlightColor() {
    final cs = Theme.of(context).colorScheme;
    final blended = Color.alphaBlend(
      cs.primary.withValues(alpha: 0.22),
      cs.surface,
    );
    final rgb = blended.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0')}';
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
}
