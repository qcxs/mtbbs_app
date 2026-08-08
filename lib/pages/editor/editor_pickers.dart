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
          _contentCtl.wrapInline('', '', ' $bbcode ');
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
    _contentCtl.insertLink(url, text: text);
    _focusContent();
  }

  /// 表情选择底部面板
  void _showEmojiPickerSheet(List<Map<String, dynamic>> groups) {
    final frequentEmojis = EmojiService().frequentlyUsed;
    showModalBottomSheet(
      context: context,
      constraints: const BoxConstraints(maxWidth: 500, maxHeight: 420),
      builder: (ctx) => EmojiPickerSheet(
        groups: groups,
        frequentEmojis: frequentEmojis,
        onEmojiPicked: (emoji) {
          final insertText = emoji['insertText'] as String;
          final smilieId = emoji['smilieId'] as String;
          _contentCtl.wrapInline('', '', insertText);
          EmojiService().recordUsage(smilieId);
          _focusContent();
        },
      ),
    );
  }

  /// 图片管理底部面板
  void _showImagePickerSheet() {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      showToast('请先登录');
      return;
    }
    if (_pageData.uploadHash.isEmpty) {
      showToast('页面数据未加载，无法上传');
      return;
    }
    // 同步活跃 AID
    _syncPendingAids();

    showModalBottomSheet(
      context: context,
      constraints: const BoxConstraints(maxWidth: 500, maxHeight: 450),
      builder: (_) => ValueListenableBuilder<_ImageSheetData>(
        valueListenable: _imageSheetDataNotifier,
        builder: (_, data, __) => ImagePickerSheet(
          images: data.images,
          loading: data.loading,
          ignoredAids: _ignoredAids,
          contentText: _contentCtl.text,
          controller: _contentCtl,
          onUpload: _handleImageUpload,
          onDelete: _handleImageDelete,
          onIgnore: _handleImageIgnore,
          onRefresh: _refreshImageList,
          onInsert: (aid) {
            _contentCtl.wrapInline('', '', '[attachimg]$aid[/attachimg]');
            _syncPendingAids();
          },
          allowedExtensions: _pageData.imageExtensions.isNotEmpty
              ? _pageData.imageExtensions
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
    if (_pageData.uploadHash.isEmpty) {
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
          contentText: _contentCtl.text,
          controller: _contentCtl,
          onUpload: _handleAttachmentUpload,
          onDelete: _handleAttachmentDelete,
          onRefresh: _refreshAttachmentList,
          onInsert: (aid) {
            _contentCtl.wrapInline('', '', '[attach]$aid[/attach]');
          },
          allowedExtensions: _pageData.attachmentExtensions.isNotEmpty
              ? _pageData.attachmentExtensions
              : null,
        ),
      ),
    );
  }
}
