part of 'editor_page.dart';

/// 图片/附件管理 — 列表刷新、上传、删除、忽略、AID 同步与预览预处理。
///
/// 通过 `part of` 与 editor_page.dart 共享库内私有成员；
/// 扩展方式拆分，避免 mixin `on` 自引用造成接口循环。
extension on _EditorPageState {
  // ==================== BBCode 预处理（预览用） ====================

  /// 预览前处理：将 [attachimg] 替换为 [img]，将 [attach] 替换为卡片
  String _preparePreviewBbcode(String bbcode) {
    // 处理图片附件 [attachimg]
    bbcode = bbcode.replaceAllMapped(
      RegExp(r'\[attachimg\](\d+)\[/attachimg\]'),
      (m) {
        final aid = m.group(1) ?? '';
        final src = _aidToSrc[aid] ?? '';
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

  // ==================== 图片管理 ====================

  /// 同步图片数据到 notifier（让图片管理面板重建）
  void _syncImagesNotifier() {
    _imageSheetDataNotifier.value = _ImageSheetData(
      _imageList.where((i) => !_ignoredAids.contains(i['aid'])).toList(),
      _loadingImages,
    );
  }

  /// 刷新图片列表（合并页面已有 + 已上传未绑定的图片）
  Future<void> _refreshImageList() async {
    try {
      final fid = _pageData.fid.isNotEmpty ? _pageData.fid : widget.fid;
      final tid = _pageData.tid.isNotEmpty ? _pageData.tid : widget.tid;

      AppLogger.i(
        'EDITOR',
        jsonEncode({'action': 'refreshImageList', 'fid': fid, 'tid': tid}),
      );
      _setState(() => _loadingImages = true);
      _syncImagesNotifier();
      final images = await upload_api.fetchUnusedImages(
        ApiService().dio,
        fid: fid,
        tid: tid.isNotEmpty ? tid : null,
      );
      if (!mounted) return;
      int newCount = 0;
      _setState(() {
        for (final img in images) {
          final aid = img['aid']?.toString() ?? '';
          final src = img['src']?.toString() ?? '';
          if (aid.isEmpty || src.isEmpty) continue;
          // 合并到 _imageList（去重）
          if (!_imageList.any((i) => i['aid'] == aid)) {
            _imageList.add({
              'aid': aid,
              'src': src,
              'title': img['title']?.toString() ?? '',
              'type': 'uploaded',
            });
            newCount++;
          }
          // 同时更新 _aidToSrc（供预览用）
          if (!_aidToSrc.containsKey(aid)) {
            _aidToSrc[aid] = src;
          }
        }
        _loadingImages = false;
      });
      _syncImagesNotifier();
      AppLogger.i(
        'EDITOR',
        jsonEncode({
          'action': 'refreshImageList_done',
          'total': _imageList.length,
          'new': newCount,
        }),
      );
    } catch (_) {
      AppLogger.w('EDITOR', 'refreshImageList failed');
      if (mounted) {
        _setState(() => _loadingImages = false);
        _syncImagesNotifier();
      }
    }
  }

  /// 处理图片上传（选择文件 → 上传 → 加入列表）
  Future<void> _handleImageUpload() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) return;
    if (_pageData.uploadHash.isEmpty) return;

    final imgExts = _pageData.imageExtensions;
    final result = await FilePicker.platform.pickFiles(
      type: imgExts.isNotEmpty ? FileType.custom : FileType.image,
      allowedExtensions: imgExts.isNotEmpty ? imgExts : null,
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
        final uploadResult = await upload_api.uploadImage(
          ApiService().dio,
          file: file,
          uid: auth.uid,
          uploadHash: _pageData.uploadHash,
        );
        if (!mounted) return;
        if (uploadResult['success'] == true) {
          final aid = uploadResult['aid']?.toString() ?? '';
          final src = uploadResult['src']?.toString() ?? '';
          final title = uploadResult['title']?.toString() ?? '';
          if (aid.isNotEmpty && src.isNotEmpty) {
            _setState(() {
              _imageList.add({
                'aid': aid,
                'src': src,
                'title': title,
                'type': 'uploaded',
              });
              _aidToSrc[aid] = src;
            });
            successCount++;
          }
          // 上传成功后清理 file_picker 复制的临时缓存文件（Android）
          await deleteFilePickerTempIfAny(filePath);
        } else {
          failCount++;
        }
      } finally {}
    }
    _syncImagesNotifier();

    AppLogger.i(
      'EDITOR',
      jsonEncode({
        'action': 'handleImageUpload',
        'success': successCount,
        'fail': failCount,
        'totalFiles': result.files.length,
        'imageListSize': _imageList.length,
      }),
    );

    if (!mounted) return;
    if (successCount > 0 && failCount == 0) {
      showToast('上传成功 $successCount 张图片');
    } else if (successCount > 0 && failCount > 0) {
      showToast('上传完成：成功 $successCount 张，失败 $failCount 张');
    } else {
      showToast('上传失败');
    }
  }

  /// 删除图片（调用 API 删除 + 从本地列表移除）
  Future<void> _handleImageDelete(String aid) async {
    final ok = await upload_api.deleteUnusedImage(
      ApiService().dio,
      formhash: _pageData.formhash,
      tid: _pageData.tid.isNotEmpty ? _pageData.tid : widget.tid,
      pid: _pageData.pid.isNotEmpty ? _pageData.pid : widget.pid,
      aid: aid,
    );
    if (!mounted) return;
    if (ok) {
      _setState(() {
        _imageList.removeWhere((i) => i['aid'] == aid);
        _aidToSrc.remove(aid);
      });
      _syncImagesNotifier();
      AppLogger.i(
        'EDITOR',
        jsonEncode({'action': 'deleteImage', 'aid': aid, 'success': true}),
      );
      showToast('已删除');
    } else {
      AppLogger.w(
        'EDITOR',
        jsonEncode({'action': 'deleteImage', 'aid': aid, 'success': false}),
      );
      showToast('删除失败');
    }
  }

  /// 忽略图片（从显示列表中隐藏）
  void _handleImageIgnore(String aid) {
    _setState(() {
      _ignoredAids.add(aid);
      _imageList.removeWhere((i) => i['aid'] == aid);
      _aidToSrc.remove(aid);
    });
    _syncImagesNotifier();
  }

  /// 获取当前活跃的 AID 集合（未忽略的图片）
  Set<String> get _activeAids {
    return _imageList
        .map((i) => i['aid'] as String)
        .where((aid) => !_ignoredAids.contains(aid))
        .toSet();
  }

  /// 同步活跃 AID 到 BBCodeController
  void _syncPendingAids() {
    _contentCtl.pendingAids
      ..clear()
      ..addAll(_activeAids);
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
      final fid = _pageData.fid.isNotEmpty ? _pageData.fid : widget.fid;
      final tid = _pageData.tid.isNotEmpty ? _pageData.tid : widget.tid;

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
    if (_pageData.uploadHash.isEmpty) return;

    final attExts = _pageData.attachmentExtensions;
    final result = await FilePicker.platform.pickFiles(
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
          uploadHash: _pageData.uploadHash,
          fid: _pageData.fid.isNotEmpty ? _pageData.fid : widget.fid,
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
      formhash: _pageData.formhash,
      tid: _pageData.tid.isNotEmpty ? _pageData.tid : widget.tid,
      pid: _pageData.pid.isNotEmpty ? _pageData.pid : widget.pid,
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

  /// 上传图片到论坛（默认上传），成功后插入 [attachimg]
  Future<void> _uploadDefaultImage(File file) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn || _pageData.uploadHash.isEmpty) {
      if (mounted) showToast('未登录或无上传权限');
      return;
    }

    try {
      final uploadResult = await upload_api.uploadImage(
        ApiService().dio,
        file: file,
        uid: auth.uid,
        uploadHash: _pageData.uploadHash,
      );
      if (!mounted) return;
      if (uploadResult['success'] == true) {
        final aid = uploadResult['aid']?.toString() ?? '';
        final src = uploadResult['src']?.toString() ?? '';
        final title = uploadResult['title']?.toString() ?? '';
        if (aid.isNotEmpty && src.isNotEmpty) {
          _setState(() {
            _imageList.add({
              'aid': aid,
              'src': src,
              'title': title,
              'type': 'uploaded',
            });
            _aidToSrc[aid] = src;
          });
          _syncImagesNotifier();
          _contentCtl.wrapInline('', '', '[attachimg]$aid[/attachimg]');
          _focusContent();
        }
        if (mounted) showToast('剪贴板图片已上传');
      } else {
        if (mounted) showToast('上传失败: ${uploadResult['error'] ?? '未知错误'}');
      }
    } catch (e) {
      if (mounted) showToast('上传失败: $e');
    }
  }
}
