import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mtbbs/core/utils/cache_utils.dart';
import 'package:mtbbs/core/utils/url_util.dart';
import 'package:mtbbs/widgets/bbcode/bbcode_controller.dart';
import 'package:mtbbs/widgets/common/app_sheet.dart';

/// 图片管理面板 — 纯 UI 组件
///
/// 图片数据由调用方持有（完整编辑器 `EditorPage` / 迷你编辑器的图片抽屉
/// `showForumImageDrawer`），面板仅负责展示和交互回调。上传/删除/忽略等
/// 操作通过回调修改调用方数据，面板关闭重开不会丢失数据。
class ImagePickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> images;
  final bool loading;
  final Set<String> ignoredAids;
  final String contentText;
  final BBCodeController controller;
  final Future<void> Function() onUpload;
  final Future<void> Function(String aid) onDelete;
  final void Function(String aid) onIgnore;
  final VoidCallback onRefresh;
  final void Function(String aid) onInsert;
  final List<String>? allowedExtensions;

  /// 宽屏侧栏模式：隐藏拖拽手柄、插入后不关闭、关闭按钮走 [onClose]。
  ///
  /// 默认 `false` 保持底部抽屉（窄屏 / 迷你编辑器）原有行为。
  final bool embedded;

  /// 侧栏模式的关闭回调（[embedded] 为 true 时必传）
  final VoidCallback? onClose;

  const ImagePickerSheet({
    super.key,
    required this.images,
    required this.loading,
    required this.ignoredAids,
    required this.contentText,
    required this.controller,
    required this.onUpload,
    required this.onDelete,
    required this.onIgnore,
    required this.onRefresh,
    required this.onInsert,
    this.allowedExtensions,
    this.embedded = false,
    this.onClose,
  });

  @override
  State<ImagePickerSheet> createState() => _ImagePickerSheetState();
}

class _ImagePickerSheetState extends State<ImagePickerSheet> {
  String? _selectedAid;
  bool _uploading = false;

  bool get _hasSelection => _selectedAid != null && _selectedAid!.isNotEmpty;

  @override
  void didUpdateWidget(ImagePickerSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果选中项在更新后不存在了，清空选中
    if (_selectedAid != null &&
        !widget.images.any((i) => i['aid'] == _selectedAid)) {
      _selectedAid = null;
    }
  }

  Future<void> _pickAndUpload() async {
    setState(() => _uploading = true);
    try {
      await widget.onUpload();
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// 检查某张图片是否已在内容区中插入
  bool _isInserted(String aid) {
    return widget.contentText.contains('[attachimg]$aid[/attachimg]');
  }

  void _viewImage(String aid) {
    final img = widget.images.cast<Map<String, dynamic>?>().firstWhere(
      (i) => i?['aid'] == aid,
      orElse: () => null,
    );
    if (img == null) return;
    final src = img['src'] as String? ?? '';
    if (src.isEmpty) return;
    final fullSrc = normalizeUrl(src);

    context.push(
      '/image-viewer',
      extra: {
        'urls': [fullSrc],
        'index': 0,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveDisabled = _uploading;
    return Column(
      // 侧栏是全高抽屉；底部抽屉仍按内容收缩
      mainAxisSize: widget.embedded ? MainAxisSize.max : MainAxisSize.min,
      children: [
        // 拖拽手柄（仅底部抽屉）
        if (!widget.embedded) const SheetDragHandle(),
        // 标题栏 + 恢复 + 关闭
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Row(
            children: [
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '图片管理',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (widget.allowedExtensions != null &&
                        widget.allowedExtensions!.isNotEmpty)
                      Text(
                        '支持 ${widget.allowedExtensions!.join(', ')}',
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    if (widget.embedded)
                      Text(
                        '插入后不关闭，可连续插入',
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: widget.loading ? null : widget.onRefresh,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: '恢复',
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: widget.embedded
                    ? widget.onClose
                    : () => Navigator.of(context).pop(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: '关闭',
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // 操作工具栏（上图下字 + 居右）
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _toolBtn(
                Icons.cloud_upload_outlined,
                '上传',
                _uploading,
                _pickAndUpload,
              ),
              _toolBtn(
                Icons.add_photo_alternate_outlined,
                '插入',
                !_hasSelection || effectiveDisabled,
                () {
                  if (_selectedAid == null) return;
                  final aid = _selectedAid!;
                  widget.onInsert(aid);
                  if (widget.embedded) {
                    // 侧栏不收起；清空选中，避免误重复插入同一张
                    setState(() => _selectedAid = null);
                  } else {
                    Navigator.of(context).pop();
                  }
                },
              ),
              _toolBtn(Icons.delete_outline, '删除', !_hasSelection, () {
                if (_selectedAid != null) widget.onDelete(_selectedAid!);
              }),
              _toolBtn(Icons.visibility_off_outlined, '忽略', !_hasSelection, () {
                if (_selectedAid != null) widget.onIgnore(_selectedAid!);
              }),
              _toolBtn(Icons.visibility_outlined, '查看', !_hasSelection, () {
                if (_selectedAid != null) _viewImage(_selectedAid!);
              }),
            ],
          ),
        ),
        const Divider(height: 1),
        // 图片网格
        Expanded(child: _buildImageGrid()),
      ],
    );
  }

  Widget _toolBtn(
    IconData icon,
    String label,
    bool disabled,
    VoidCallback onTap,
  ) {
    final cs = Theme.of(context).colorScheme;
    final effectiveDisabled = disabled || _uploading;
    // 侧栏最窄 240px，5 个按钮必须收紧，否则 Row 会溢出
    final compact = widget.embedded;
    return Padding(
      padding: EdgeInsets.only(left: compact ? 2 : 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: effectiveDisabled ? null : onTap,
        child: Opacity(
          opacity: effectiveDisabled ? 0.35 : 1.0,
          child: Container(
            constraints: BoxConstraints(minWidth: compact ? 36 : 48),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: effectiveDisabled ? cs.onSurfaceVariant : null,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: effectiveDisabled ? cs.onSurfaceVariant : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageGrid() {
    final cs = Theme.of(context).colorScheme;
    if (widget.loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (widget.images.isEmpty) {
      return Center(
        child: Text(
          '暂无已上传的图片',
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
        ),
      );
    }
    return GridView.extent(
      maxCrossAxisExtent: 80,
      crossAxisSpacing: 6,
      mainAxisSpacing: 6,
      padding: const EdgeInsets.all(12),
      childAspectRatio: 1,
      children: widget.images.map((img) {
        final aid = img['aid'] as String;
        final src = img['src'] as String;
        final isSelected = _selectedAid == aid;
        final inserted = _isInserted(aid);
        final fullSrc = normalizeUrl(src);
        return GestureDetector(
          onTap: () => setState(() {
            _selectedAid = isSelected ? null : aid;
          }),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  imageUrl: fullSrc,
                  cacheManager: imageCacheManager,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    color: cs.surfaceContainerLow,
                    child: Icon(Icons.broken_image, color: cs.onSurfaceVariant),
                  ),
                ),
              ),
              if (isSelected)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: cs.onSurfaceVariant,
                        width: 2.5,
                      ),
                    ),
                  ),
                ),
              if (inserted)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(6),
                        topRight: Radius.circular(6),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.55),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 11,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '已插入',
                          style: TextStyle(fontSize: 10, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(6),
                      bottomRight: Radius.circular(6),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.55),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    '#$aid',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
