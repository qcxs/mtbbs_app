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
}
