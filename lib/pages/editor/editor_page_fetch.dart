part of 'editor_page.dart';

/// 页面/引用数据抓取 — 从绑定的 Discuz 页面提取会话数据，以及引用帖加载。
extension on _EditorPageState {
  Future<void> _doFetchPage({bool preserveContent = false}) async {
    _setState(() {
      _loadingPage = true;
      _pageError = null;
    });
    final result = await _session.submitHelper.fetchPage(
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
        _setState(() {
          _loadingPage = false;
          _pageError = null;
          _session.pageData = const PageFormData(success: true);
        });
        return;
      }
      _setState(() {
        _loadingPage = false;
        _pageError = result.error ?? '加载失败';
      });
      return;
    }

    bool shouldSaveInitial = false;
    _setState(() {
      _session.pageData = result;
      _loadingPage = false;
      _pageError = null;
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
        if (result.title.isNotEmpty) _session.titleCtl.text = result.title;
        if (result.content.isNotEmpty)
          _session.contentCtl.text = result.content;
        if (result.title.isNotEmpty || result.content.isNotEmpty) {
          shouldSaveInitial = true;
        }
      }
    });
    // 图片列表 + aid→src 映射（由 ForumImageController 通知页面重建）
    _images.setFromPageImages(result.images, preserve: preserveContent);

    if (!preserveContent) {
      _initialTitle = _session.titleCtl.text;
      _initialContent = _session.contentCtl.text;
      _initialPendingAids = Set.from(_session.contentCtl.pendingAids);
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
    _images.refresh();
    _refreshAttachmentList();
  }

  Future<void> _doFetchQuotedPost() async {
    _setState(() {
      _loadingQuoted = true;
      _quotedError = null;
    });
    final post = await _session.submitHelper.fetchQuotedPost();
    if (!mounted) return;
    if (post != null) {
      _setState(() {
        _session.quotedPost = post;
        _loadingQuoted = false;
      });
    } else {
      _setState(() {
        _quotedError = '获取失败';
        _loadingQuoted = false;
      });
    }
  }
}
