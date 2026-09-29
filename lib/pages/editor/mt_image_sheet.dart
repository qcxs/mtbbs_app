import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mtbbs/core/utils/cache_utils.dart';
import 'package:mtbbs/core/utils/formatters.dart';
import 'package:mtbbs/core/utils/string_utils.dart';
import 'package:mtbbs/pages/settings/mt_image_manage_sheet.dart';
import 'package:mtbbs/services/mt_image_hosting.dart';
import 'package:mtbbs/services/clipboard_paste.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';

part 'mt_image_sheet_build.dart';
part 'mt_image_sheet_widgets.dart';

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
        final name = basename(clipImg.path);
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
      withReadStream: true,
      allowCompression: false,
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
        onError: (msg) {
          if (mounted) showToast(msg);
        },
      );
      // 上传成功后清理 file_picker 复制的临时缓存文件（Android）
      if (result != null) await deleteFilePickerTempIfAny(item.path);
      if (!mounted) return;
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

  /// 供 part 扩展使用（扩展无法直接访问受保护的 setState）
  void _setState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  @override
  Widget build(BuildContext context) => _buildPage(context);
}
