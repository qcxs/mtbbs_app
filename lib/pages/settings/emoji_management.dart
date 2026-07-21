import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mtbbs/core/cache_utils.dart';
import 'package:mtbbs/core/emoji_loader.dart';

/// 表情管理页 — 查看当前站点的所有表情分组和列表
class EmojiManagementPage extends StatefulWidget {
  const EmojiManagementPage({super.key});

  @override
  State<EmojiManagementPage> createState() => _EmojiManagementPageState();
}

class _EmojiManagementPageState extends State<EmojiManagementPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _groups = [];
  final Set<int> _expandedGroups = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await EmojiService().load();
      if (!mounted) return;
      final groups = EmojiService().groups;
      if (groups.isEmpty) {
        setState(() {
          _loading = false;
          _error = '暂无表情数据（可能未登录或站点不支持）';
        });
      } else {
        setState(() {
          _groups = groups;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await EmojiService().refresh();
      if (!mounted) return;
      setState(() {
        _groups = List<Map<String, dynamic>>.from(EmojiService().groups);
        _loading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _groups.isNotEmpty ? '表情已更新，共 ${_emojiTotal()} 个' : '暂无表情数据',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  int _emojiTotal() {
    int total = 0;
    for (final g in _groups) {
      total += (g['emojis'] as List).length;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('表情管理'),
        surfaceTintColor: cs.surface,
        actions: [
          if (!_loading)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '重新获取',
              onPressed: _refresh,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.emoji_emotions_outlined,
                size: 48,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_groups.isEmpty) {
      return Center(
        child: Text('暂无表情数据', style: TextStyle(color: cs.onSurfaceVariant)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _groups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _buildGroupCard(_groups[i]),
    );
  }

  Widget _buildGroupCard(Map<String, dynamic> group) {
    final cs = Theme.of(context).colorScheme;
    final id = group['id'] as int;
    final name = group['name'] as String;
    final folder = group['folder'] as String;
    final emojis = group['emojis'] as List<dynamic>;
    final expanded = _expandedGroups.contains(id);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() {
              if (expanded) {
                _expandedGroups.remove(id);
              } else {
                _expandedGroups.add(id);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '$folder · ${emojis.length} 个表情',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) _buildEmojiGrid(emojis),
        ],
      ),
    );
  }

  Widget _buildEmojiGrid(List<dynamic> emojis) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: emojis
            .map((e) => _buildEmojiItem(e as Map<String, dynamic>))
            .toList(),
      ),
    );
  }

  Widget _buildEmojiItem(Map<String, dynamic> emoji) {
    final cs = Theme.of(context).colorScheme;
    final smilieId = emoji['smilieId'] as String;
    final insertText = emoji['insertText'] as String;
    final imageUrl = emoji['imageUrl'] as String;

    return GestureDetector(
      onTap: () => _showEmojiDetail(emoji),
      child: Tooltip(
        message: '$insertText (smilieId: $smilieId)',
        child: Container(
          width: 60,
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    cacheManager: emojiCacheManager,
                    width: 32,
                    height: 32,
                    errorWidget: (_, __, ___) => Icon(
                      Icons.emoji_emotions_outlined,
                      size: 24,
                      color: cs.onSurfaceVariant,
                    ),
                    placeholder: (_, __) => SizedBox(
                      width: 32,
                      height: 32,
                      child: Center(
                        child: SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                color: cs.surfaceContainerLow,
                child: Text(
                  insertText,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEmojiDetail(Map<String, dynamic> emoji) {
    final cs = Theme.of(context).colorScheme;
    final smilieId = emoji['smilieId'] as String;
    final insertText = emoji['insertText'] as String;
    final imageUrl = emoji['imageUrl'] as String;
    final groupName =
        _groups.firstWhere(
              (g) => (g['emojis'] as List<dynamic>).any(
                (e) => (e as Map<String, dynamic>)['smilieId'] == smilieId,
              ),
              orElse: () => <String, dynamic>{'name': ''},
            )['name']
            as String;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 350),
        title: Row(
          children: [
            const Expanded(child: Text('表情详情', style: TextStyle(fontSize: 16))),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.of(ctx).pop(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                cacheManager: emojiCacheManager,
                width: 64,
                height: 64,
                errorWidget: (_, __, ___) => Icon(
                  Icons.emoji_emotions_outlined,
                  size: 48,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _infoRow('insertText', insertText),
            _infoRow('smilieId', smilieId),
            _infoRow('分组', groupName),
            _infoRow('图片 URL', imageUrl),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
