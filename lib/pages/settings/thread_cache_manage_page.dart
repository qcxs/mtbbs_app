import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/auth/providers/auth_provider.dart';
import 'package:mtbbs/core/utils/formatters.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/core/utils/thread_cache_database.dart';
import 'package:mtbbs/models/thread_snapshot.dart';
import 'package:mtbbs/pages/settings/widgets/dialogs.dart';
import 'package:mtbbs/pages/thread/thread_view_page.dart';
import 'package:mtbbs/platform/optional/file_pick.dart';
import 'package:mtbbs/platform/optional/file_save.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/services/thread_cache_service.dart';
import 'package:mtbbs/services/thread_cache_transfer.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';
import 'package:mtbbs/widgets/dialog/confirm_dialog.dart';
import 'package:mtbbs/widgets/layout/state_views.dart';

part 'thread_cache_manage_auto.dart';
part 'thread_cache_manage_offline.dart';
part 'thread_cache_manage_transfer.dart';

/// 帖子缓存管理页（自动缓存 / 离线帖子）。
///
/// 只负责展示与触发服务层操作，不直接读写 sembast。
/// 按业务分 part：自动缓存 / 离线帖子 / 导入导出与损坏恢复。
class ThreadCacheManagePage extends StatefulWidget {
  const ThreadCacheManagePage({super.key});

  @override
  State<ThreadCacheManagePage> createState() => _ThreadCacheManagePageState();
}

class _ThreadCacheManagePageState extends State<ThreadCacheManagePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  final ThreadCacheService _service = ThreadCacheService.instance;
  final ThreadCacheTransfer _transfer = ThreadCacheTransfer.instance;

  bool _loading = true;
  ThreadCacheStats _stats = const ThreadCacheStats();
  int _fileBytes = 0;
  List<ThreadSnapshotMeta> _auto = const [];
  List<ThreadSnapshotMeta> _offline = const [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _service.health.addListener(_onHealthChanged);
    _refresh();
  }

  @override
  void dispose() {
    _service.health.removeListener(_onHealthChanged);
    _tab.dispose();
    super.dispose();
  }

  void _onHealthChanged() {
    if (!mounted) return;
    _refresh();
  }

  String get _viewer => context.read<AuthProvider>().uid;

  bool get _corrupted => _service.isDisabled;

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _loading = true);
    if (_corrupted) {
      setState(() {
        _loading = false;
        _stats = const ThreadCacheStats();
        _fileBytes = 0;
        _auto = const [];
        _offline = const [];
      });
      return;
    }
    await _service.cleanExpired();
    final stats = await _service.stats();
    final bytes = await _service.fileSizeBytes();
    final auto = await _service.listAuto(viewer: _viewer);
    final offline = await _service.listOffline();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _stats = stats;
      _fileBytes = bytes;
      _auto = auto;
      _offline = offline;
    });
  }

  // ==================== 构建 ====================

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('帖子缓存'),
        surfaceTintColor: cs.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: '刷新',
            onPressed: _refresh,
          ),
          IconButton(
            icon: const Icon(Icons.file_download_outlined, size: 20),
            tooltip: '导入',
            onPressed: _corrupted ? null : _handleImport,
          ),
          IconButton(
            icon: const Icon(Icons.file_upload_outlined, size: 20),
            tooltip: '导出',
            onPressed: _handleExport,
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: '自动缓存'),
            Tab(text: '离线帖子'),
          ],
        ),
      ),
      body: _loading
          ? const LoadingView()
          : _corrupted
          ? _buildCorruptedBody()
          : Column(
              children: [
                _buildSummary(),
                const _UnencryptedHint(),
                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: [_buildAutoTab(), _buildOfflineTab()],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSummary() {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _chip(
                  cs,
                  '自动缓存',
                  '${_stats.autoThreads} 帖 / ${_stats.autoVersions} 版本',
                ),
                _chip(cs, '自动占用', formatBytes(_stats.autoBytes)),
                _chip(cs, '离线帖子', '${_stats.offlineThreads} 帖'),
                _chip(cs, '离线占用', formatBytes(_stats.offlineBytes)),
                _chip(cs, '文件', formatBytes(_fileBytes)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '单帖上限 ${formatBytes(_service.maxBytesPerThread)}'
              '（自动缓存按该帖全部版本合计）',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(ColorScheme cs, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
      ),
    );
  }
}

/// 未加密提示（两个 Tab / 损坏态都始终可见）
class _UnencryptedHint extends StatelessWidget {
  const _UnencryptedHint();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Row(
        children: [
          Icon(Icons.lock_open, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '缓存与导出文件未加密，请勿公开分享。',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
