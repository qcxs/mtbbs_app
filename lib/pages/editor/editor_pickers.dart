part of 'editor_page.dart';

/// 各类弹窗/底部面板 — 历史记录、MT 图床、表情、图片、附件选择。
extension on _EditorPageState {
  /// 插入历史记录弹窗
  void _showHistoryDialog() {
    final history = context.read<HistoryProvider>();
    if (history.totalCount == 0) {
      showToast('暂无浏览记录');
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
          _session.contentCtl.wrapInline('', '', ' $bbcode ');
          _focusContent();
        },
      ),
    );
  }

  /// 插入一条浏览记录（按站点设置的历史格式）
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
    _session.contentCtl.insertLink(url, text: text);
    _focusContent();
  }

  /// 图片管理底部面板（状态与动作见 [ForumImageController]；面板本身是纯 UI）
  void _showImagePickerSheet() {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      showToast('请先登录');
      return;
    }
    if (_session.pageData.uploadHash.isEmpty) {
      showToast('页面数据未加载，无法上传');
      return;
    }
    // 同步活跃 AID（上传但未插入正文的图片，提交时经 attachnew 绑定）
    _images.syncPendingAids();

    // 宽屏：固定右侧栏（无遮罩，可连续插入）；窄屏保持底部抽屉
    if (MediaQuery.sizeOf(context).isWide) {
      _setState(() => _showImagePanel = !_showImagePanel);
      return;
    }

    showModalBottomSheet(
      context: context,
      constraints: const BoxConstraints(maxWidth: 500, maxHeight: 450),
      builder: (_) => ListenableBuilder(
        listenable: _images,
        builder: (_, __) => ImagePickerSheet(
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
          },
          allowedExtensions: _session.pageData.imageExtensions.isNotEmpty
              ? _session.pageData.imageExtensions
              : null,
        ),
      ),
    );
  }

  /// 附件管理底部面板
  void _showAttachmentPickerSheet() {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      showToast('请先登录');
      return;
    }
    if (_session.pageData.uploadHash.isEmpty) {
      showToast('页面数据未加载，无法上传');
      return;
    }

    showModalBottomSheet(
      context: context,
      constraints: const BoxConstraints(maxWidth: 500, maxHeight: 450),
      builder: (ctx) => ValueListenableBuilder<_AttachmentSheetData>(
        valueListenable: _attachmentSheetDataNotifier,
        builder: (_, data, __) => AttachmentPickerSheet(
          attachments: data.attachments,
          loading: data.loading,
          contentText: _session.contentCtl.text,
          controller: _session.contentCtl,
          onUpload: _handleAttachmentUpload,
          onDelete: _handleAttachmentDelete,
          onRefresh: _refreshAttachmentList,
          onInsert: (aid) {
            _session.contentCtl.wrapInline('', '', '[attach]$aid[/attach]');
          },
          allowedExtensions: _session.pageData.attachmentExtensions.isNotEmpty
              ? _session.pageData.attachmentExtensions
              : null,
        ),
      ),
    );
  }
}
