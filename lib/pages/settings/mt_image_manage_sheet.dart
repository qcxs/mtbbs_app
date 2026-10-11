import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mtbbs/core/utils/cache_utils.dart';
import 'package:mtbbs/core/utils/clipboard_helper.dart';
import 'package:mtbbs/core/utils/formatters.dart';
import 'package:mtbbs/services/mt_image_hosting.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';
import 'package:mtbbs/widgets/dialog/confirm_dialog.dart';
import 'package:mtbbs/widgets/image_preview/image_preview.dart';

/// MT 图床管理面板 — 查看/删除历史上传。
///
/// 只有列表操作、没有设置表单，因此以底部面板承载，不再占用独立路由。
Future<void> showMtImageManageSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560, maxHeight: 600),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (_) => const _MtImageManageSheet(),
  );
}

class _MtImageManageSheet extends StatefulWidget {
  const _MtImageManageSheet();

  @override
  State<_MtImageManageSheet> createState() => _MtImageManageSheetState();
}

class _MtImageManageSheetState extends State<_MtImageManageSheet> {
  final MtImageHosting _hosting = MtImageHosting();
  List<MtUploadResult> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _hosting.getHistory(limit: 200);
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  Future<void> _delete(MtUploadResult item) async {
    final confirm = await showConfirmDialog(
      context,
      title: '确认删除',
      message: '确定永久删除「${item.originName}」的上传记录吗？',
      confirmText: '删除',
    );
    if (confirm != true) return;
    await _hosting.deleteHistory(item.url);
    _load();
  }

  /// 点击眼镜图标：用通用大图查看器查看（可左右滑动切换）
  void _openGallery(int index) {
    showImageViewer(
      context,
      imageUrls: _items.map((e) => e.url).toList(),
      initialIndex: index,
    );
  }

  /// 查看信息：文件名 / 大小 / 时间 / 链接（可复制）
  void _showInfo(MtUploadResult item) {
    showDialog<void>(
      context: context,
      builder: (_) => _MtImageInfoDialog(item: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        // 拖拽手柄
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
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
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'MT 图床管理',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        Expanded(child: _buildBody(cs)),
      ],
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          '暂无历史记录',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
        ),
      );
    }
    return ListView.builder(
      itemCount: _items.length,
      itemBuilder: (_, i) {
        final item = _items[i];
        return ListTile(
          onTap: () => _showInfo(item),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: CachedNetworkImage(
              imageUrl: item.thumbnailUrl.isNotEmpty
                  ? item.thumbnailUrl
                  : item.url,
              cacheManager: imageCacheManager,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(
                width: 48,
                height: 48,
                color: cs.surfaceContainerHigh,
                child: Icon(Icons.image, size: 24, color: cs.onSurfaceVariant),
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
            '${item.sizeText}  ·  ${formatRelativeTimeShort(item.uploadedAt)}',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.visibility_outlined, size: 20),
                tooltip: '查看大图',
                visualDensity: VisualDensity.compact,
                onPressed: () => _openGallery(i),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  switch (v) {
                    case 'info':
                      _showInfo(item);
                    case 'delete':
                      _delete(item);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'info', child: Text('查看信息')),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('删除', style: TextStyle(color: cs.error)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 单条上传记录的信息弹窗 — 预览 + 可复制的链接
class _MtImageInfoDialog extends StatelessWidget {
  const _MtImageInfoDialog({required this.item});

  final MtUploadResult item;

  Future<void> _copy(String text) async {
    await ClipboardHelper.write(text);
    showToast('已复制');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('图片信息', style: TextStyle(fontSize: 16)),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 预览图
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  imageUrl: item.url,
                  cacheManager: imageCacheManager,
                  width: double.infinity,
                  height: 160,
                  fit: BoxFit.contain,
                  errorWidget: (_, __, ___) => Container(
                    height: 160,
                    alignment: Alignment.center,
                    color: cs.surfaceContainerHigh,
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _metaRow(cs, '文件名', item.originName),
              _metaRow(cs, '大小', item.sizeText),
              _metaRow(cs, '上传时间', formatDateTimeFull(item.uploadedAt)),
              const SizedBox(height: 8),
              _CopyField(label: '原图链接', value: item.url, onCopy: _copy),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _metaRow(ColorScheme cs, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

/// 可复制字段：标签 + 只读值 + 复制按钮
class _CopyField extends StatelessWidget {
  const _CopyField({
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final String label;
  final String value;
  final Future<void> Function(String text) onCopy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: SelectableText(
                  value,
                  maxLines: 4,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: '复制',
                visualDensity: VisualDensity.compact,
                onPressed: () => onCopy(value),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
