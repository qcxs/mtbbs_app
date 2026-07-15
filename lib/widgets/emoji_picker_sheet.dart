import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/cache_utils.dart';

/// 表情面板 — 底部弹出，支持分组浏览/锁定连续插入/常用表情
class EmojiPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> groups;
  final List<Map<String, dynamic>> frequentEmojis;
  final void Function(Map<String, dynamic> emoji) onEmojiPicked;

  const EmojiPickerSheet({
    super.key,
    required this.groups,
    required this.frequentEmojis,
    required this.onEmojiPicked,
  });

  @override
  State<EmojiPickerSheet> createState() => _EmojiPickerSheetState();
}

class _EmojiPickerSheetState extends State<EmojiPickerSheet> {
  int _selectedIndex = 0;
  bool _locked = false;

  List<_TabItem> get _tabs {
    final tabs = <_TabItem>[_TabItem('常用', widget.frequentEmojis)];
    for (final g in widget.groups) {
      tabs.add(_TabItem(g['name'] as String, g['emojis'] as List<dynamic>));
    }
    return tabs;
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 拖拽手柄
        Padding(
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
        ),
        // Tab 栏 + 关闭按钮
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: List.generate(tabs.length, (i) {
                      final tab = tabs[i];
                      final selected = i == _selectedIndex;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedIndex = i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: selected
                                ? Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.1)
                                : null,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            tab.label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  _locked ? Icons.lock_outline : Icons.lock_open_outlined,
                  size: 18,
                ),
                onPressed: () => setState(() => _locked = !_locked),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: _locked ? '解锁' : '锁定',
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.of(context).pop(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // 表情网格
        Expanded(child: _buildEmojiGrid(tabs)),
      ],
    );
  }

  Widget _buildEmojiGrid(List<_TabItem> tabs) {
    final currentEmojis = tabs[_selectedIndex].emojis;
    if (currentEmojis.isEmpty) {
      return Center(
        child: Text(
          _selectedIndex == 0 ? '暂无常用表情' : '暂无表情',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
        ),
      );
    }
    return GridView.extent(
      maxCrossAxisExtent: 42,
      crossAxisSpacing: 4,
      mainAxisSpacing: 4,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      childAspectRatio: 1,
      children: currentEmojis.map((e) {
        final emoji = e as Map<String, dynamic>;
        final imageUrl = emoji['imageUrl'] as String;
        return GestureDetector(
          onTap: () {
            if (!_locked) Navigator.of(context).pop();
            widget.onEmojiPicked(emoji);
          },
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                cacheManager: emojiCacheManager,
                width: 30,
                height: 30,
                errorWidget: (_, __, ___) => Icon(
                  Icons.emoji_emotions_outlined,
                  size: 22,
                  color: Colors.grey.shade400,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _TabItem {
  final String label;
  final List<dynamic> emojis;
  _TabItem(this.label, this.emojis);
}
