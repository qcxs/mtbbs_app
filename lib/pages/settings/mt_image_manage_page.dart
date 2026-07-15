import 'package:flutter/material.dart';
import '../../services/mt_image_hosting.dart';

/// MT 图床管理页面 — 查看/删除/隐藏历史上传
class MtImageManagePage extends StatefulWidget {
  const MtImageManagePage({super.key});

  @override
  State<MtImageManagePage> createState() => _MtImageManagePageState();
}

class _MtImageManagePageState extends State<MtImageManagePage> {
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定永久删除「${item.originName}」的上传记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
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
    return Scaffold(
      appBar: AppBar(title: const Text('MT 图床管理'), centerTitle: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _items.isEmpty
          ? Center(
              child: Text(
                '暂无历史记录',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
              ),
            )
          : ListView.builder(
              itemCount: _items.length,
              itemBuilder: (_, i) {
                final item = _items[i];
                return ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.network(
                      item.thumbnailUrl.isNotEmpty
                          ? item.thumbnailUrl
                          : item.url,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 48,
                        height: 48,
                        color: Colors.grey.shade200,
                        child: const Icon(
                          Icons.image,
                          size: 24,
                          color: Colors.grey,
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
                      color: item.hidden ? Colors.grey : null,
                    ),
                  ),
                  subtitle: Text(
                    '${item.sizeText}  ·  ${_dateText(item.uploadedAt)}'
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
                        child: Text(
                          '删除',
                          style: TextStyle(color: Colors.red.shade400),
                        ),
                      ),
                    ],
                  ),
                );
              },
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
}
