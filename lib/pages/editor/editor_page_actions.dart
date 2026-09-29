part of 'editor_page.dart';

/// 退出确认、提交发布与历史快照恢复。
extension on _EditorPageState {
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

    _setState(() => _isSubmitting = true);

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

        // 发帖成功：直接打开新帖，覆盖编辑器路由（返回时回到来源页，编辑器不留在栈里）
        if (widget.type == EditorType.post &&
            !result.needsApproval &&
            result.tid.isNotEmpty) {
          AppLogger.i(
            'EDITOR',
            jsonEncode({'action': 'open_new_thread', 'tid': result.tid}),
          );
          context.replace('/thread/${result.tid}');
          return;
        }
        Navigator.of(context).pop({'success': true, 'result': result});
      } else {
        _setState(() => _isSubmitting = false);
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
        _setState(() => _isSubmitting = false);
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
    _setState(() {});
    _doFetchPage(preserveContent: true);
    showToast('已恢复快照，正在刷新页面数据...');
    AppLogger.i('EDITOR', 'restored snapshot: $snapshotId');
  }
}

String _typeLabel(String type) {
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
