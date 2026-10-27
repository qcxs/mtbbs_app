part of 'thread_cache_manage_page.dart';

/// 帖子缓存管理页 — 导入导出与损坏恢复。
extension on _ThreadCacheManagePageState {
  // ==================== 导入 / 导出 ====================

  Future<void> _handleExport() async {
    if (_corrupted) {
      showToast('缓存不可用，请使用下方「抢救导出」');
      return;
    }
    final kind = _tab.index == 0
        ? ThreadCacheKind.auto
        : ThreadCacheKind.offline;
    final snapshots = await _transfer.collectForExport(
      kind: kind,
      viewer: kind == ThreadCacheKind.auto ? _viewer : null,
    );
    if (!mounted) return;
    if (snapshots.isEmpty) {
      showToast('当前没有可导出的内容');
      return;
    }
    final content = _transfer.buildExportJson(snapshots);
    final fileName =
        'mtbbs_threads_${ThreadCacheTransfer.timestampForFileName()}.json';
    final outcome = await FileSave.saveText(
      content,
      fileName: fileName,
      dialogTitle: '导出帖子缓存',
      allowedExtensions: const ['json'],
    );
    if (!mounted) return;
    switch (outcome) {
      case FileSaveOutcome.saved:
        showToast('已导出 ${snapshots.length} 条');
        break;
      case FileSaveOutcome.canceled:
        break;
      case FileSaveOutcome.unavailable:
      case FileSaveOutcome.failed:
        final path = await _transfer.writeExportFallback(content);
        if (mounted)
          showToast('已保存到 $path', duration: const Duration(seconds: 4));
    }
  }

  Future<void> _handleImport() async {
    final picked = await FilePick.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) {
      if (mounted) showToast('已取消');
      return;
    }
    final file = picked.files.first;
    if (file.size > 100 * 1024 * 1024) {
      showToast('文件过大（超过 100 MB）');
      return;
    }
    String? json;
    try {
      if (file.bytes != null) {
        json = utf8.decode(file.bytes!, allowMalformed: true);
      } else if (file.path != null) {
        json = await File(file.path!).readAsString();
      }
    } catch (e) {
      AppLogger.w('THREAD_CACHE', 'read import file failed: $e');
      if (mounted) showToast('读取文件失败');
      return;
    }
    if (json == null) {
      if (mounted) showToast('读取文件失败');
      return;
    }
    if (!mounted) return;

    final preview = await _transfer.preview(json, viewer: _viewer);
    if (!mounted) return;
    if (!preview.valid) {
      showToast(preview.error ?? '文件格式不正确');
      return;
    }
    if (preview.importableCount <= 0) {
      showToast('没有可导入的条目');
      return;
    }

    // 离线冲突策略（有冲突时询问）
    var overwriteOffline = false;
    if (preview.conflictOffline > 0) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('离线帖子冲突'),
          content: Text('有 ${preview.conflictOffline} 条离线副本已存在，如何处理？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('跳过全部冲突'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('覆盖全部冲突'),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      overwriteOffline = choice;
    }

    final confirmed = await showConfirmDialog(
      context,
      title: '导入帖子缓存',
      message:
          '共 ${preview.total} 条，可导入 ${preview.importableCount} 条。\n'
          '自动缓存 ${preview.autoCount} 条，离线 ${preview.offlineCount} 条。\n'
          '冲突 ${preview.conflictAuto + preview.conflictOffline} 条，'
          '损坏/超限 ${preview.invalidCount + preview.oversizedCount} 条。',
      confirmText: '导入',
    );
    if (confirmed != true || !mounted) return;

    final result = await _transfer.importJson(
      json,
      viewer: _viewer,
      overwriteOffline: overwriteOffline,
    );
    if (!mounted) return;
    await _showImportResult(result);
    await _refresh();
  }

  Future<void> _showImportResult(ThreadCacheImportResult result) async {
    if (result.fatal) {
      showToast(result.message ?? '导入失败');
      return;
    }
    final lines = <String>[
      '成功导入 ${result.imported} 条',
      if (result.skipped > 0) '跳过 ${result.skipped} 条（含冲突）',
      if (result.tooLarge > 0) '超限 ${result.tooLarge} 条',
      if (result.failed > 0) '失败 ${result.failed} 条',
    ];
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入完成'),
        content: Text(lines.join('\n')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  // ==================== 损坏态 ====================

  Widget _buildCorruptedBody() {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          color: cs.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: cs.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '帖子缓存文件损坏，缓存功能已禁用',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: cs.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '自动缓存与离线保存已暂停。建议先导出备份，再重建或清空缓存库。',
                  style: TextStyle(fontSize: 13, color: cs.onErrorContainer),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: _handleExportRaw,
                      child: const Text('导出原始文件'),
                    ),
                    OutlinedButton(
                      onPressed: _handleBestEffortExport,
                      child: const Text('尽力导出 JSON'),
                    ),
                    FilledButton(
                      onPressed: _handleRebuild,
                      child: const Text('重建缓存库'),
                    ),
                    OutlinedButton(
                      onPressed: _handleClearAndRebuild,
                      child: const Text('清空缓存库'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        const _UnencryptedHint(),
      ],
    );
  }

  Future<void> _handleExportRaw() async {
    final dir = await FileSave.pickDirectory(dialogTitle: '选择备份目录');
    if (dir == null) {
      if (mounted) showToast('已取消或当前平台不支持选择目录');
      return;
    }
    final saved = await _transfer.copyRawTo(dir);
    if (!mounted) return;
    showToast(saved == null ? '原始文件不存在或复制失败' : '已备份到 $saved');
  }

  Future<void> _handleBestEffortExport() async {
    final auto = await _transfer.collectForExport(kind: ThreadCacheKind.auto);
    final offline = await _transfer.collectForExport(
      kind: ThreadCacheKind.offline,
    );
    final all = [...auto, ...offline];
    if (!mounted) return;
    if (all.isEmpty) {
      showToast('没有可解析的记录');
      return;
    }
    final content = _transfer.buildExportJson(all);
    final fileName =
        'mtbbs_threads_rescue_${ThreadCacheTransfer.timestampForFileName()}.json';
    final outcome = await FileSave.saveText(
      content,
      fileName: fileName,
      dialogTitle: '尽力导出 JSON',
      allowedExtensions: const ['json'],
    );
    if (!mounted) return;
    if (outcome == FileSaveOutcome.saved) {
      showToast('已导出 ${all.length} 条');
    } else if (outcome != FileSaveOutcome.canceled) {
      final path = await _transfer.writeExportFallback(content);
      if (mounted) {
        showToast('已保存到 $path', duration: const Duration(seconds: 4));
      }
    }
  }

  Future<void> _handleRebuild() async {
    final confirmed = await showConfirmDialog(
      context,
      title: '重建缓存库',
      message:
          '原文件会重命名为 .corrupt-时间 备份，随后创建空库。'
          '离线帖子将从备份文件中恢复，不会自动导入。',
      confirmText: '重建',
      danger: true,
    );
    if (confirmed != true || !mounted) return;
    var ok = await _service.rebuild();
    if (!ok && mounted) {
      final remove = await showConfirmDialog(
        context,
        title: '无法重命名备份',
        message: '是否直接删除损坏文件后重建？原文件将无法恢复。',
        confirmText: '删除并重建',
        danger: true,
      );
      if (remove == true && mounted) {
        ok = await _service.rebuild(deleteIfRenameFails: true);
      }
    }
    if (!mounted) return;
    showToast(ok ? '缓存库已重建，功能恢复' : '重建失败');
    await _refresh();
  }

  Future<void> _handleClearAndRebuild() async {
    final confirmed = await showConfirmDialog(
      context,
      title: '清空缓存库',
      message: '将直接删除缓存文件并重建，自动缓存与离线帖子都会丢失。',
      confirmText: '清空',
      danger: true,
    );
    if (confirmed != true || !mounted) return;
    final ok = await _service.clearAndRebuild();
    if (!mounted) return;
    showToast(ok ? '缓存库已清空重建' : '清空失败');
    await _refresh();
  }
}
