import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mtbbs/core/parser/md2bbcode.dart';
import 'package:mtbbs/widgets/bbcode/post_html_widget.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';
import 'package:mtbbs/widgets/dialog/confirm_dialog.dart';

/// 导入方式
enum MdImportMode {
  /// 替换编辑器正文
  replace,

  /// 插入到光标处
  insert,
}

/// 底部面板的返回结果
class MdImportResult {
  final String bbcode;
  final MdImportMode mode;

  const MdImportResult(this.bbcode, this.mode);
}

/// 打开「导入 Markdown」底部面板。
///
/// 面板只负责「Markdown → BBCode」的编辑与预览，返回 [MdImportResult]；
/// 真正的写入由调用方（编辑器）完成，避免本组件持有编辑器状态。
///
/// [editorHasContent] 为 true 时，选择「替换正文」会先二次确认。
Future<MdImportResult?> showMdImportSheet(
  BuildContext context, {
  bool editorHasContent = false,
}) {
  final maxHeight = MediaQuery.sizeOf(context).height * 0.86;
  return showModalBottomSheet<MdImportResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // Expanded 依赖上界，必须给 maxHeight（见 docs/07 #53）
    constraints: BoxConstraints(maxWidth: 720, maxHeight: maxHeight),
    builder: (_) => _MdImportSheet(editorHasContent: editorHasContent),
  );
}

class _MdImportSheet extends StatefulWidget {
  final bool editorHasContent;

  const _MdImportSheet({required this.editorHasContent});

  @override
  State<_MdImportSheet> createState() => _MdImportSheetState();
}

class _MdImportSheetState extends State<_MdImportSheet> {
  final _mdCtl = TextEditingController();
  final _mdFocus = FocusNode();

  /// 0 = Markdown 输入 / 1 = 预览 / 2 = BBCode 源码
  int _tab = 0;

  /// 转换选项（默认保留 Emoji：App 侧表情可正常渲染，不需要像 mt-convert 那样默认剔除）
  bool _removeEmoji = false;
  bool _autoNumbering = false;

  String _bbcode = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _mdCtl.dispose();
    _mdFocus.dispose();
    super.dispose();
  }

  // ==================== 转换 ====================

  void _onInputChanged() {
    setState(() {}); // 刷新底部字数统计
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), _convert);
  }

  void _convert() {
    if (!mounted) return;
    final out = markdownToBbcode(
      _mdCtl.text,
      autoNumbering: _autoNumbering,
      removeEmoji: _removeEmoji,
    );
    if (out != _bbcode) setState(() => _bbcode = out);
  }

  // ==================== 操作 ====================

  Future<void> _pickFile() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['md', 'markdown', 'txt'],
        withData: true,
        allowCompression: false,
      );
    } catch (e) {
      if (mounted) showToast('无法打开文件选择器: $e');
      return;
    }
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    String? content;
    try {
      final bytes = file.bytes;
      if (bytes != null) {
        content = utf8.decode(bytes, allowMalformed: true);
      } else if (file.path != null) {
        content = await File(file.path!).readAsString();
      }
    } catch (e) {
      if (mounted) showToast('读取文件失败: $e');
      return;
    }
    if (content == null || !mounted) return;

    _mdCtl.text = content;
    _convert();
    if (mounted) showToast('已载入 ${file.name}');
  }

  Future<void> _copy() async {
    if (_bbcode.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _bbcode));
    if (mounted) showToast('已复制 BBCode', duration: const Duration(seconds: 1));
  }

  Future<void> _apply(MdImportMode mode) async {
    if (_bbcode.isEmpty) {
      showToast('没有可用的转换结果');
      return;
    }
    if (mode == MdImportMode.replace && widget.editorHasContent) {
      final ok = await showConfirmDialog(
        context,
        title: '替换正文',
        message: '将用转换结果替换编辑器中的全部内容（可用撤销恢复）。',
        confirmText: '替换',
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(MdImportResult(_bbcode, mode));
  }

  // ==================== Build ====================

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _dragHandle(),
        _header(),
        const Divider(height: 1),
        Expanded(child: _body()),
        const Divider(height: 1),
        _actionBar(),
      ],
    );
  }

  Widget _dragHandle() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Center(
        child: Container(
          width: 32,
          height: 4,
          decoration: BoxDecoration(
            color: cs.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  /// 标题 + 右上角的三个 tab + 选项菜单 + 关闭
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 4, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '导入 Markdown',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _segmented(),
          PopupMenuButton<String>(
            icon: const Icon(Icons.tune, size: 20),
            iconSize: 20,
            padding: EdgeInsets.zero,
            tooltip: '转换选项',
            onSelected: (value) {
              switch (value) {
                case 'emoji':
                  setState(() => _removeEmoji = !_removeEmoji);
                  _convert();
                case 'numbering':
                  setState(() => _autoNumbering = !_autoNumbering);
                  _convert();
                case 'clear':
                  _mdCtl.clear();
                  setState(() => _bbcode = '');
              }
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: 'emoji',
                checked: _removeEmoji,
                child: const Text('去除 Emoji'),
              ),
              CheckedPopupMenuItem(
                value: 'numbering',
                checked: _autoNumbering,
                child: const Text('标题自动编号'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'clear', child: Text('清空输入')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: '关闭',
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  /// 右上角的三段式 tab：MD / 预览 / BBCode
  Widget _segmented() {
    final cs = Theme.of(context).colorScheme;

    Widget seg(int index, String label) {
      final selected = _tab == index;
      return InkWell(
        onTap: () => setState(() => _tab = index),
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? cs.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? cs.onPrimary : cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [seg(0, 'MD'), seg(1, '预览'), seg(2, 'BBCode')],
      ),
    );
  }

  Widget _body() {
    switch (_tab) {
      case 1:
        return _previewTab();
      case 2:
        return _bbcodeTab();
      default:
        return _inputTab();
    }
  }

  Widget _inputTab() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '支持 GFM：标题 / 列表 / 表格 / 代码块 / 任务列表 / 链接',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.file_open_outlined, size: 16),
                label: const Text('从文件导入', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            child: TextField(
              controller: _mdCtl,
              focusNode: _mdFocus,
              onChanged: (_) => _onInputChanged(),
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(fontSize: 13, height: 1.5),
              decoration: const InputDecoration(
                hintText: '在此粘贴或输入 Markdown…',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.all(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _previewTab() {
    final cs = Theme.of(context).colorScheme;
    if (_bbcode.isEmpty) {
      return Center(
        child: Text(
          '输入 Markdown 后可预览',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      // 复用编辑器预览同款渲染链路，所见即论坛最终效果
      child: PostHtmlWidget(bbcode: _bbcode),
    );
  }

  Widget _bbcodeTab() {
    final cs = Theme.of(context).colorScheme;
    if (_bbcode.isEmpty) {
      return Center(
        child: Text('暂无转换结果', style: TextStyle(color: cs.onSurfaceVariant)),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: SelectableText(
        _bbcode,
        style: const TextStyle(fontSize: 13, height: 1.5),
      ),
    );
  }

  Widget _actionBar() {
    final cs = Theme.of(context).colorScheme;
    final enabled = _bbcode.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_mdCtl.text.length} 字符 → ${_bbcode.length} 字符',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton.icon(
            onPressed: enabled ? _copy : null,
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('复制'),
          ),
          const SizedBox(width: 4),
          OutlinedButton(
            onPressed: enabled ? () => _apply(MdImportMode.insert) : null,
            child: const Text('插入'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: enabled ? () => _apply(MdImportMode.replace) : null,
            child: const Text('替换正文'),
          ),
        ],
      ),
    );
  }
}
