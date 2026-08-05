import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/core/utils/cache_utils.dart';
import 'package:mtbbs/core/app/emoji_loader.dart';
import 'package:mtbbs/core/app/avatar_redirect_store.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/models/post_preview.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';
import 'package:mtbbs/widgets/dialog/confirm_dialog.dart';

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
  ({int bytes, int files})? _imageInfo;
  ({int bytes, int files})? _medalInfo;
  ({int bytes, int files})? _filePickerInfo;
  bool _loadingAvatar = true;
  bool _loadingEmoji = true;
  bool _loadingImage = true;
  bool _loadingMedal = true;
  bool _loadingFilePicker = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _loadAvatarInfo();
    _loadEmojiInfo();
    _loadImageInfo();
    _loadMedalInfo();
    _loadFilePickerInfo();
  }

  Future<void> _loadImageInfo() async {
    setState(() => _loadingImage = true);
    final info = await getCacheInfo('image_cache');
    if (mounted)
      setState(() {
        _imageInfo = info;
        _loadingImage = false;
      });
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

  Future<void> _loadMedalInfo() async {
    setState(() => _loadingMedal = true);
    final info = await getCacheInfo('medal_cache');
    if (mounted)
      setState(() {
        _medalInfo = info;
        _loadingMedal = false;
      });
  }

  Future<void> _loadFilePickerInfo() async {
    setState(() => _loadingFilePicker = true);
    final info = await getCacheInfo('file_picker');
    if (mounted)
      setState(() {
        _filePickerInfo = info;
        _loadingFilePicker = false;
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
    String? subtitle,
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
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
            onClear: () => _clearAndRefresh(
              'avatar_cache',
              '头像图片缓存',
              _loadAvatarInfo,
              // 清除头像缓存时一并清空重定向映射，避免映射指向已清除的旧缓存
              extraClear: () => AvatarRedirectStore.instance.clear(),
            ),
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
            onClear: () =>
                _clearAndRefresh('emoji_cache', '表情图片缓存', _loadEmojiInfo),
            onSettings: () => _showDayPicker(
              title: '表情缓存过期',
              currentDays: settings.emojiCacheDays,
              onSave: (days) => settings.setEmojiCacheDays(days),
            ),
          ),

          // 帖子图片缓存
          _buildCacheTile(
            title: '帖子图片缓存',
            sizeText: _imageInfo != null
                ? AppLogger.bytes(_imageInfo!.bytes)
                : null,
            countText: _imageInfo != null ? '${_imageInfo!.files} 个' : null,
            loading: _loadingImage,
            onClear: () =>
                _clearAndRefresh('image_cache', '帖子图片缓存', _loadImageInfo),
            onSettings: () => _showDayPicker(
              title: '帖子图片缓存过期',
              currentDays: settings.imageCacheDays,
              onSave: (days) => settings.setImageCacheDays(days),
            ),
          ),

          // 勋章图片缓存
          _buildCacheTile(
            title: '勋章图片缓存',
            sizeText: _medalInfo != null
                ? AppLogger.bytes(_medalInfo!.bytes)
                : null,
            countText: _medalInfo != null ? '${_medalInfo!.files} 个' : null,
            loading: _loadingMedal,
            onClear: () =>
                _clearAndRefresh('medal_cache', '勋章图片缓存', _loadMedalInfo),
            onSettings: () => _showDayPicker(
              title: '勋章缓存过期',
              currentDays: settings.medalCacheDays,
              onSave: (days) => settings.setMedalCacheDays(days),
            ),
          ),

          // 文件选择器缓存
          _buildCacheTile(
            title: '文件选择器缓存',
            subtitle: 'file_picker 选取文件时复制的临时副本（Android）',
            sizeText: _filePickerInfo != null
                ? AppLogger.bytes(_filePickerInfo!.bytes)
                : null,
            countText: _filePickerInfo != null
                ? '${_filePickerInfo!.files} 个'
                : null,
            loading: _loadingFilePicker,
            onClear: () =>
                _clearAndRefresh('file_picker', '文件选择器缓存', _loadFilePickerInfo),
          ),

          // 浏览器缓存
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              title: const Text('浏览器缓存'),
              subtitle: const Text('内置浏览器的网页资源、Cookie、Web 存储'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              trailing: TextButton.icon(
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('清空'),
                style: TextButton.styleFrom(
                  foregroundColor: cs.error,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () async {
                  if (!await _confirmClear('浏览器缓存')) return;
                  await clearWebViewCache();
                  if (mounted) {
                    showToast('浏览器缓存已清空');
                  }
                },
              ),
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
                onPressed: () async {
                  if (!await _confirmClear('表情元数据')) return;
                  EmojiService().clearCache();
                  if (mounted) {
                    showToast('表情元数据已清空');
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
                  if (!await _confirmClear('帖子预览缓存')) return;
                  await PostPreviewManager.instance.clear();
                  if (mounted) {
                    showToast('帖子预览缓存已清空');
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

  /// 二次确认后清空缓存
  Future<bool> _confirmClear(String name) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '确认清空',
      message: '确定要清空 $name 吗？此操作不可恢复。',
      confirmText: '清空',
      danger: true,
    );
    return confirmed == true;
  }

  Future<void> _clearAndRefresh(
    String cacheKey,
    String label,
    Future<void> Function() refreshFn, {
    Future<void> Function()? extraClear,
  }) async {
    if (!await _confirmClear(label)) return;
    await clearCacheByKey(cacheKey);
    await extraClear?.call();
    if (mounted) refreshFn();
  }
}
