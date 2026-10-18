part of 'editor_page.dart';

/// 图片/附件媒体 — 预览预处理（图片/附件）与附件管理（列表/上传/删除）。
///
/// 图片管理的**状态与动作**已抽到 [ForumImageController]（完整版持久持有、
/// 迷你版图片抽屉临时持有，两份共用一份实现，见 forum_image_controller.dart）；
/// 这里只保留预览预处理与附件管理。
extension on _EditorPageState {
  // ==================== BBCode 预处理（预览用） ====================

  /// 预览前处理：将 [attachimg] 替换为 [img]，将 [attach] 替换为卡片
  String _preparePreviewBbcode(String bbcode) {
    // 处理图片附件 [attachimg]
    bbcode = bbcode.replaceAllMapped(
      RegExp(r'\[attachimg\](\d+)\[/attachimg\]'),
      (m) {
        final aid = m.group(1) ?? '';
        final src = _images.aidToSrc[aid] ?? '';
        if (src.isNotEmpty) {
          final data = jsonEncode({
            'type': 'image_attach',
            'url': src,
            'aid': aid,
          });
          return '[appdata]$data[/appdata]';
        }
        return m.group(0)!;
      },
    );
    // 处理文件附件 [attach]
    bbcode = bbcode.replaceAllMapped(RegExp(r'\[attach\](\d+)\[/attach\]'), (
      m,
    ) {
      final aid = m.group(1) ?? '';
      final att = _aidToAttachment[aid];
      if (att != null) {
        final data = jsonEncode({
          'type': 'attach',
          'name': att['name'],
          'size': att['size'],
          'url': att['url'],
        });
        return '[appdata]$data[/appdata]';
      }
      return m.group(0)!;
    });
    return bbcode;
  }

  // ==================== 附件管理 ====================

  /// 同步附件数据到 notifier
  void _syncAttachmentsNotifier() {
    _attachmentSheetDataNotifier.value = _AttachmentSheetData(
      List.from(_attachmentList),
      _loadingAttachments,
    );
  }

  /// 从附件条目构建预览信息
  Map<String, String> _buildAttachInfo(Map<String, dynamic> att) {
    final aid = att['aid'] as String? ?? '';
    final title = att['title'] as String? ?? '';
    final sizeMatch = RegExp(r'文件大小:\s*([^ ]+)').firstMatch(title);
    return {
      'name': att['filename'] as String? ?? '附件 #$aid',
      'size': sizeMatch?.group(1) ?? '',
      'url': 'forum.php?mod=attachment&aid=$aid',
    };
  }

  /// 刷新附件列表
  Future<void> _refreshAttachmentList() async {
    try {
      final fid = _session.pageData.fid.isNotEmpty
          ? _session.pageData.fid
          : widget.fid;
      final tid = _session.pageData.tid.isNotEmpty
          ? _session.pageData.tid
          : widget.tid;

      AppLogger.i(
        'EDITOR',
        jsonEncode({'action': 'refreshAttachmentList', 'fid': fid, 'tid': tid}),
      );
      _setState(() => _loadingAttachments = true);
      _syncAttachmentsNotifier();
      final attachments = await upload_api.fetchUnusedAttachments(
        ApiService().dio,
        fid: fid,
        tid: tid.isNotEmpty ? tid : null,
      );
      if (!mounted) return;
      int mergeCount = 0;
      _setState(() {
        // 合并已绑定附件 + 未使用附件
        final merged = <Map<String, dynamic>>[];
        // 先添加已绑定的（从 _aidToAttachment 重建条目）
        for (final entry in _aidToAttachment.entries) {
          merged.add({
            'aid': entry.key,
            'filename': entry.value['name'] ?? '',
            'title': '',
            'isimage': '0',
            'icon': '',
            'bound': true,
          });
        }
        // 再添加未使用的（去重）
        for (final att in attachments) {
          final aid = att['aid'] as String? ?? '';
          if (aid.isNotEmpty && !merged.any((m) => m['aid'] == aid)) {
            merged.add(att);
          }
          // 补充 _aidToAttachment 映射
          if (aid.isNotEmpty && !_aidToAttachment.containsKey(aid)) {
            _aidToAttachment[aid] = _buildAttachInfo(att);
            mergeCount++;
          }
        }
        _attachmentList = merged;
        _loadingAttachments = false;
      });
      _syncAttachmentsNotifier();
      AppLogger.i(
        'EDITOR',
        jsonEncode({
          'action': 'refreshAttachmentList_done',
          'count': _attachmentList.length,
          'merged': mergeCount,
          'boundTotal': _aidToAttachment.length,
        }),
      );
    } catch (_) {
      AppLogger.w('EDITOR', 'refreshAttachmentList failed');
      if (mounted) {
        _setState(() => _loadingAttachments = false);
        _syncAttachmentsNotifier();
      }
    }
  }

  /// 处理附件上传
  Future<void> _handleAttachmentUpload() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) return;
    if (_session.pageData.uploadHash.isEmpty) return;

    final attExts = _session.pageData.attachmentExtensions;
    final result = await FilePick.pickFiles(
      type: attExts.isNotEmpty ? FileType.custom : FileType.any,
      allowedExtensions: attExts.isNotEmpty ? attExts : null,
      allowMultiple: true,
      withReadStream: true,
      allowCompression: false,
    );
    if (result == null || result.files.isEmpty) return;

    int successCount = 0;
    int failCount = 0;
    for (final f in result.files) {
      final filePath = f.path;
      if (filePath == null) {
        failCount++;
        continue;
      }

      final file = File(filePath);
      try {
        final uploadResult = await upload_api.uploadAttachment(
          ApiService().dio,
          file: file,
          uid: auth.uid,
          uploadHash: _session.pageData.uploadHash,
          fid: _session.pageData.fid.isNotEmpty
              ? _session.pageData.fid
              : widget.fid,
        );
        if (!mounted) return;
        if (uploadResult['success'] == true) {
          final aid = uploadResult['aid']?.toString() ?? '';
          if (aid.isNotEmpty) {
            final name = uploadResult['filename']?.toString() ?? '';
            _aidToAttachment[aid] = {
              'name': name,
              'size': '',
              'url': 'forum.php?mod=attachment&aid=$aid',
            };
          }
          successCount++;
          // 上传成功后清理 file_picker 复制的临时缓存文件（Android）
          await deleteFilePickerTempIfAny(filePath);
        } else {
          failCount++;
        }
      } finally {}
    }
    _syncAttachmentsNotifier();

    AppLogger.i(
      'EDITOR',
      jsonEncode({
        'action': 'handleAttachmentUpload',
        'success': successCount,
        'fail': failCount,
        'totalFiles': result.files.length,
        'boundTotal': _aidToAttachment.length,
      }),
    );

    if (!mounted) return;
    if (successCount > 0 && failCount == 0) {
      showToast('上传成功 $successCount 个附件');
    } else if (successCount > 0 && failCount > 0) {
      showToast('上传完成：成功 $successCount 个，失败 $failCount 个');
    } else {
      showToast('上传失败');
    }
  }

  /// 删除附件
  Future<void> _handleAttachmentDelete(String aid) async {
    final ok = await upload_api.deleteUnusedImage(
      ApiService().dio,
      formhash: _session.pageData.formhash,
      tid: _session.pageData.tid.isNotEmpty
          ? _session.pageData.tid
          : widget.tid,
      pid: _session.pageData.pid.isNotEmpty
          ? _session.pageData.pid
          : widget.pid,
      aid: aid,
    );
    if (!mounted) return;
    if (ok) {
      _setState(() {
        _attachmentList.removeWhere((i) => i['aid'] == aid);
        _aidToAttachment.remove(aid);
      });
      _syncAttachmentsNotifier();
      AppLogger.i(
        'EDITOR',
        jsonEncode({'action': 'deleteAttachment', 'aid': aid, 'success': true}),
      );
      showToast('已删除');
    } else {
      AppLogger.w(
        'EDITOR',
        jsonEncode({
          'action': 'deleteAttachment',
          'aid': aid,
          'success': false,
        }),
      );
      showToast('删除失败');
    }
  }

  /// 剪贴板图片上传 → 插入 [attachimg]（默认上传）
  Future<void> _uploadDefaultImage(File file) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn || _session.pageData.uploadHash.isEmpty) {
      if (mounted) showToast('未登录或无上传权限');
      return;
    }
    final up = await _images.uploadFile(file);
    if (!mounted) return;
    if (up != null) {
      _session.contentCtl.wrapInline(
        '',
        '',
        '[attachimg]${up['aid']}[/attachimg]',
      );
      _focusContent();
      showToast('剪贴板图片已上传');
    } else {
      showToast('上传失败');
    }
  }
}
