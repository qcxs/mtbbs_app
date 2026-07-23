import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/cache_utils.dart';
import '../../core/emoji_loader.dart';
import '../../core/logger.dart';
import '../../models/post_preview.dart';
import '../../providers/settings_provider.dart';

/// 缓存管理页面
///
/// 查看各缓存大小、清空、设置过期时间。
class CacheSettingsPage extends StatefulWidget {
  const CacheSettingsPage({super.key});

  @override
  State<CacheSettingsPage> createState() => _CacheSettingsPageState();
}

class _CacheSettingsPageState extends State<CacheSettingsPage> {
  // 缓存信息（异步加载）
  ({int bytes, int files})? _avatarInfo;
  ({int bytes, int files})? _emojiInfo;
  bool _loadingAvatar = true;
  bool _loadingEmoji = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _loadAvatarInfo();
    _loadEmojiInfo();
  }

  Future<void> _loadAvatarInfo() async {
    setState(() => _loadingAvatar = true);
    final info = await getCacheInfo('avatar_cache');
    if (mounted)
      setState(() {
        _avatarInfo = info;
        _loadingAvatar = false;
      });
  }

  Future<void> _loadEmojiInfo() async {
    setState(() => _loadingEmoji = true);
    final info = await getCacheInfo('emoji_cache');
    if (mounted)
      setState(() {
        _emojiInfo = info;
        _loadingEmoji = false;
      });
  }

  // ==================== 过期天数选择弹窗 ====================

  static const _dayOptions = [
    (-1, '永不过期'),
    (1, '1 天'),
    (3, '3 天'),
    (7, '7 天'),
    (14, '14 天'),
    (30, '30 天'),
    (90, '90 天'),
  ];

  void _showDayPicker({
    required String title,
    required int currentDays,
    required Future<void> Function(int days) onSave,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _dayOptions.map((opt) {
            final days = opt.$1;
            final label = opt.$2;
            return RadioListTile<int>(
              title: Text(label),
              value: days,
              groupValue: currentDays,
              onChanged: (v) {
                if (v == null) return;
                Navigator.of(ctx).pop();
                onSave(v);
              },
              dense: true,
            );
          }).toList(),
        ),
      ),
    );
  }

  // ==================== 构建 ====================

  Widget _buildCacheTile({
    required String title,
    required String? sizeText,
    required String? countText,
    required bool loading,
    required VoidCallback onClear,
    VoidCallback? onSettings,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('清空'),
                  style: TextButton.styleFrom(
                    foregroundColor: cs.error,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: onClear,
                ),
                if (onSettings != null)
                  TextButton.icon(
                    icon: const Icon(Icons.settings, size: 16),
                    label: const Text('过期'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: onSettings,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (loading)
              const LinearProgressIndicator()
            else ...[
              Row(
                children: [
                  _infoChip(cs, '大小', sizeText ?? '0B'),
                  const SizedBox(width: 12),
                  _infoChip(cs, '文件', countText ?? '0'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoChip(ColorScheme cs, String label, String value) {
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

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('缓存管理'),
        surfaceTintColor: cs.surface,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: '刷新',
            onPressed: _refresh,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // 头像图片缓存
          _buildCacheTile(
            title: '头像图片缓存',
            sizeText: _avatarInfo != null
                ? AppLogger.bytes(_avatarInfo!.bytes)
                : null,
            countText: _avatarInfo != null ? '${_avatarInfo!.files} 个' : null,
            loading: _loadingAvatar,
            onClear: () => _clearAndRefresh('avatar_cache', _loadAvatarInfo),
            onSettings: () => _showDayPicker(
              title: '头像缓存过期',
              currentDays: settings.avatarCacheDays,
              onSave: (days) => settings.setAvatarCacheDays(days),
            ),
          ),

          // 表情图片缓存
          _buildCacheTile(
            title: '表情图片缓存',
            sizeText: _emojiInfo != null
                ? AppLogger.bytes(_emojiInfo!.bytes)
                : null,
            countText: _emojiInfo != null ? '${_emojiInfo!.files} 个' : null,
            loading: _loadingEmoji,
            onClear: () => _clearAndRefresh('emoji_cache', _loadEmojiInfo),
            onSettings: () => _showDayPicker(
              title: '表情缓存过期',
              currentDays: settings.emojiCacheDays,
              onSave: (days) => settings.setEmojiCacheDays(days),
            ),
          ),

          // 表情元数据
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              title: const Text('表情元数据'),
              subtitle: const Text('分组、映射关系'),
              trailing: TextButton.icon(
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('清空'),
                style: TextButton.styleFrom(
                  foregroundColor: cs.error,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () {
                  EmojiService().clearCache();
                  if (mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('表情元数据已清空')));
                  }
                },
              ),
            ),
          ),

          // 帖子预览缓存
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              title: const Text('帖子预览缓存'),
              subtitle: const Text('引用/评论预览数据'),
              trailing: TextButton.icon(
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('清空'),
                style: TextButton.styleFrom(
                  foregroundColor: cs.error,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () async {
                  await PostPreviewManager.instance.clear();
                  if (mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('帖子预览缓存已清空')));
                  }
                },
              ),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _clearAndRefresh(
    String cacheKey,
    Future<void> Function() refreshFn,
  ) async {
    await clearCacheByKey(cacheKey);
    if (mounted) refreshFn();
  }
}
