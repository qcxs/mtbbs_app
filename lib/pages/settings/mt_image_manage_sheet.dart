import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mtbbs/core/utils/cache_utils.dart';
import 'package:mtbbs/core/utils/formatters.dart';
import 'package:mtbbs/services/mt_image_hosting.dart';
import 'package:mtbbs/widgets/dialog/confirm_dialog.dart';

/// MT 图床管理面板 — 查看/隐藏/删除历史上传。
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
    final list = await _hosting.getHistory(limit: 200, includeHidden: true);
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

  Future<void> _toggleHidden(MtUploadResult item) async {
    await _hosting.toggleHistoryHidden(item.url);
    _load();
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
                child: Icon(
                  Icons.image,
                  size: 24,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
          title: Text(
            item.originName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              color: item.hidden ? cs.onSurfaceVariant : null,
            ),
          ),
          subtitle: Text(
            '${item.sizeText}  ·  ${formatRelativeTimeShort(item.uploadedAt)}'
            '${item.hidden ? '  ·  已隐藏' : ''}',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'hide':
                  _toggleHidden(item);
                case 'delete':
                  _delete(item);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'hide',
                child: Text(item.hidden ? '取消隐藏' : '隐藏'),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'delete',
                child: Text('删除', style: TextStyle(color: cs.error)),
              ),
            ],
          ),
        );
      },
    );
  }
}
