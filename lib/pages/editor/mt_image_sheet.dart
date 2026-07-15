import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/mt_image_hosting.dart';
import '../../services/clipboard_paste.dart';

/// MT 图床底部抽屉 — 上传图片 + 历史记录
class MtImageSheet extends StatefulWidget {
  final MtImageHosting hosting;
  final void Function(String bbcode) onInsert;

  const MtImageSheet({
    super.key,
    required this.hosting,
    required this.onInsert,
  });

  @override
  State<MtImageSheet> createState() => _MtImageSheetState();
}

class _MtImageSheetState extends State<MtImageSheet> {
  List<MtUploadResult> _history = [];
  bool _loadingHistory = true;
  int? _selectedIndex;

  bool _authenticating = false;
  String? _authStatus;

  final List<_QueuedFile> _queue = [];
  bool _uploading = false;
  int _uploadingIndex = -1;
  double _currentProgress = 0;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _checkAuth();
  }

  // ==================== 认证 ====================

  Future<void> _checkAuth() async {
    if (widget.hosting.isAuthed) return;
    setState(() {
      _authenticating = true;
      _authStatus = '验证中…';
    });
    final ok = await widget.hosting.auth(
      onStatus: (s) {
        if (!mounted) return;
        setState(() => _authStatus = s);
      },
    );
    if (!mounted) return;
    setState(() {
      _authenticating = !ok;
      _authStatus = ok ? null : _authStatus;
    });
  }

  Future<void> _retryAuth() async {
    setState(() {
      _authenticating = true;
      _authStatus = '验证中…';
    });
    final ok = await widget.hosting.auth(
      onStatus: (s) {
        if (!mounted) return;
        setState(() => _authStatus = s);
      },
    );
    if (!mounted) return;
    setState(() {
      _authenticating = !ok;
      _authStatus = ok ? null : _authStatus;
    });
    if (ok && _queue.isNotEmpty) _processQueue();
  }

  // ==================== 队列 ====================

  Future<void> _pickFiles() async {
    // 检测剪贴板是否有图片
    final clipImg = await ClipboardPasteService.pasteImage();
    if (clipImg != null && mounted) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('选择图片来源'),
          content: const Text('检测到剪贴板中有图片：'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('clipboard'),
              child: const Text('上传剪贴板图片'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('file'),
              child: const Text('选择文件'),
            ),
          ],
        ),
      );
      if (choice == 'clipboard') {
        final name = clipImg.path.split(RegExp(r'[/\\]')).last;
        final size = await clipImg.length();
        setState(() {
          _queue.add(_QueuedFile(path: clipImg.path, name: name, size: size));
        });
        if (!_uploading && widget.hosting.isAuthed) _processQueue();
        return;
      } else if (choice == null || choice != 'file') {
        await clipImg.delete();
        return;
      }
      // choice == 'file': 继续走文件选择
      await clipImg.delete();
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;

    setState(() {
      for (final f in result.files) {
        if (f.path != null) {
          _queue.add(_QueuedFile(path: f.path!, name: f.name, size: f.size));
        }
      }
    });

    if (!_uploading && widget.hosting.isAuthed) _processQueue();
  }

  void _removeFromQueue(int index) {
    setState(() => _queue.removeAt(index));
  }

  Future<void> _processQueue() async {
    if (_uploading || _queue.isEmpty) return;
    setState(() {
      _uploading = true;
      _uploadingIndex = 0;
      _currentProgress = 0;
    });

    for (int i = 0; i < _queue.length && _uploading; i++) {
      if (!mounted) return;
      setState(() => _uploadingIndex = i);

      final item = _queue[i];
      final result = await widget.hosting.upload(
        item.path,
        onProgress: (sent, total) {
          if (!mounted) return;
          setState(() => _currentProgress = sent / total);
        },
      );
      if (!mounted) return;
      if (result != null) widget.onInsert(result.bbcode);
    }

    if (!mounted) return;
    setState(() {
      _uploading = false;
      _uploadingIndex = -1;
      _currentProgress = 0;
      _queue.clear();
    });
    _loadHistory();
  }

  // ==================== 历史 ====================

  Future<void> _loadHistory() async {
    final list = await widget.hosting.getHistory(includeHidden: false);
    if (!mounted) return;
    setState(() {
      _history = list;
      _loadingHistory = false;
    });
  }

  // ==================== Build ====================

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _dragHandle(),
          _titleBar(),
          const Divider(height: 1),
          _toolBar(),
          const Divider(height: 1),
          Expanded(child: _buildContent(scrollCtrl)),
        ],
      ),
    );
  }

  Widget _dragHandle() => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 4),
    child: Center(
      child: Container(
        width: 32,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    ),
  );

  Widget _titleBar() => Padding(
    padding: const EdgeInsets.only(right: 4),
    child: Row(
      children: [
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'MT 图床',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        if (_authenticating)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        if (_authStatus != null)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              _authStatus!,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
        IconButton(
          icon: const Icon(Icons.close, size: 20),
          onPressed: () => Navigator.of(context).pop(),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    ),
  );

  Widget _toolBar() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
    child: Row(
      children: [
        _toolBtn(Icons.add_photo_alternate_outlined, '选择图片', false, _pickFiles),
        if (_authenticating) _toolBtn(Icons.refresh, '重试验证', false, _retryAuth),
        if (_queue.isNotEmpty && !_uploading && !_authenticating)
          _toolBtn(Icons.cloud_upload_outlined, '上传队列', false, _processQueue),
        const Spacer(),
        if (_selectedIndex != null) ...[
          _toolBtn(Icons.visibility_outlined, '查看', false, _viewSelected),
          const SizedBox(width: 8),
          _toolBtn(
            Icons.add_photo_alternate_outlined,
            '插入',
            false,
            _insertSelected,
          ),
        ],
      ],
    ),
  );

  void _viewSelected() {
    if (_selectedIndex == null || _selectedIndex! >= _history.length) return;
    final item = _history[_selectedIndex!];
    context.push(
      '/image-viewer',
      extra: {
        'urls': [item.url],
        'index': 0,
      },
    );
  }

  void _insertSelected() {
    if (_selectedIndex == null || _selectedIndex! >= _history.length) return;
    widget.onInsert(_history[_selectedIndex!].bbcode);
    Navigator.of(context).pop();
  }

  Widget _buildContent(ScrollController scrollCtrl) => ListView(
    controller: scrollCtrl,
    children: [
      if (_authenticating &&
          _authStatus != null &&
          !_authStatus!.contains('验证中'))
        Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Column(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 40,
                  color: Colors.orange.shade300,
                ),
                const SizedBox(height: 8),
                Text(_authStatus!, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ),
      if (_queue.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            '待上传 (${_queue.length})',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ...List.generate(_queue.length, (i) {
          final item = _queue[i];
          final isCurrent = _uploading && i == _uploadingIndex;
          return ListTile(
            dense: true,
            leading: Icon(
              isCurrent ? Icons.cloud_upload : Icons.image_outlined,
              size: 20,
              color: isCurrent ? Colors.blue : null,
            ),
            title: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
            subtitle: isCurrent
                ? LinearProgressIndicator(value: _currentProgress)
                : Text(
                    _formatSize(item.size),
                    style: const TextStyle(fontSize: 12),
                  ),
            trailing: _uploading
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => _removeFromQueue(i),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
          );
        }),
        const Divider(),
      ],
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(
          children: [
            Icon(Icons.history, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '历史上传',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => context.push('/settings/mt-images'),
              icon: const Icon(Icons.settings, size: 16),
              label: const Text('管理', style: TextStyle(fontSize: 13)),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
      if (_loadingHistory)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        )
      else if (_history.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              '暂无历史记录',
              style: TextStyle(color: Colors.grey.shade400),
            ),
          ),
        )
      else
        ...List.generate(_history.length, (i) {
          final item = _history[i];
          final isSelected = _selectedIndex == i;
          return ListTile(
            dense: true,
            selected: isSelected,
            selectedTileColor: Theme.of(
              context,
            ).primaryColor.withValues(alpha: 0.08),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                item.thumbnailUrl.isNotEmpty ? item.thumbnailUrl : item.url,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 44,
                  height: 44,
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.image, size: 24, color: Colors.grey),
                ),
              ),
            ),
            title: Text(
              item.originName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
            subtitle: Text(
              '${item.sizeText}  ·  ${_dateText(item.uploadedAt)}',
              style: const TextStyle(fontSize: 12),
            ),
            onTap: () => setState(() => _selectedIndex = isSelected ? null : i),
          );
        }),
    ],
  );

  Widget _toolBtn(
    IconData icon,
    String label,
    bool disabled,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: disabled ? null : onTap,
        child: Opacity(
          opacity: disabled ? 0.35 : 1.0,
          child: Container(
            constraints: const BoxConstraints(minWidth: 48),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: disabled ? Colors.grey : null),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: disabled ? Colors.grey : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _dateText(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${dt.month}/${dt.day}';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _QueuedFile {
  final String path;
  final String name;
  final int size;
  const _QueuedFile({
    required this.path,
    required this.name,
    required this.size,
  });
}
