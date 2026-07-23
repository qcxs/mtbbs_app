import 'package:flutter/material.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/widgets/bbcode_controller.dart';

/// 附件管理面板 — 纯 UI 组件
///
/// 附件数据由编辑器 [EditorPage] 持有，面板仅负责展示和交互回调。
/// 上传/删除/忽略等操作通过回调修改编辑器数据。
class AttachmentPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> attachments;
  final bool loading;
  final String contentText;
  final BBCodeController controller;
  final Future<void> Function() onUpload;
  final Future<void> Function(String aid) onDelete;
  final VoidCallback onRefresh;
  final void Function(String aid) onInsert;
  final List<String>? allowedExtensions;

  const AttachmentPickerSheet({
    super.key,
    required this.attachments,
    required this.loading,
    required this.contentText,
    required this.controller,
    required this.onUpload,
    required this.onDelete,
    required this.onRefresh,
    required this.onInsert,
    this.allowedExtensions,
  });

  @override
  State<AttachmentPickerSheet> createState() => _AttachmentPickerSheetState();
}

class _AttachmentPickerSheetState extends State<AttachmentPickerSheet> {
  String? _selectedAid;

  bool get _hasSelection => _selectedAid != null && _selectedAid!.isNotEmpty;

  @override
  void didUpdateWidget(AttachmentPickerSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedAid != null &&
        !widget.attachments.any((i) => i['aid'] == _selectedAid)) {
      _selectedAid = null;
    }
  }

  /// 检查某附件是否已在内容区中插入
  bool _isInserted(String aid) {
    return widget.contentText.contains('[attach]$aid[/attach]');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        // 标题栏 + 刷新 + 关闭
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
                      '附件管理',
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
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: widget.loading ? null : widget.onRefresh,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: '刷新',
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
        // 操作工具栏
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _toolBtn(Icons.cloud_upload_outlined, '上传', false, () async {
                await widget.onUpload();
                if (mounted) widget.onRefresh();
              }),
              _toolBtn(Icons.add_link_outlined, '插入', !_hasSelection, () {
                if (_selectedAid == null) return;
                widget.onInsert(_selectedAid!);
                Navigator.of(context).pop();
              }),
              _toolBtn(Icons.delete_outline, '删除', !_hasSelection, () {
                if (_selectedAid != null) widget.onDelete(_selectedAid!);
              }),
            ],
          ),
        ),
        const Divider(height: 1),
        // 附件列表
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _toolBtn(
    IconData icon,
    String label,
    bool disabled,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: disabled ? null : onTap,
        child: Opacity(
          opacity: disabled ? 0.35 : 1.0,
          child: Container(
            constraints: const BoxConstraints(minWidth: 48),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20),
                const SizedBox(height: 2),
                Text(label, style: const TextStyle(fontSize: 10)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    final cs = Theme.of(context).colorScheme;
    if (widget.loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (widget.attachments.isEmpty) {
      return Center(
        child: Text(
          '暂无已上传的附件',
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: widget.attachments.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 44),
      itemBuilder: (context, index) {
        final att = widget.attachments[index];
        final aid = att['aid'] as String? ?? '';
        final filename = att['filename'] as String? ?? '';
        final inserted = _isInserted(aid);
        final isSelected = _selectedAid == aid;
        final baseUrl = ApiService().dio.options.baseUrl;
        final iconSrc = att['icon'] as String? ?? '';
        final iconUrl = iconSrc.startsWith('http')
            ? iconSrc
            : (iconSrc.isNotEmpty ? '$baseUrl/$iconSrc' : '');

        return InkWell(
          onTap: () => setState(() {
            _selectedAid = isSelected ? null : aid;
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: isSelected
                ? BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(6),
                  )
                : null,
            child: Row(
              children: [
                // 文件类型图标
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: iconUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            iconUrl,
                            width: 36,
                            height: 36,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.insert_drive_file_outlined,
                              size: 20,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        )
                      : Icon(
                          Icons.insert_drive_file_outlined,
                          size: 20,
                          color: cs.onSurfaceVariant,
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        filename.isNotEmpty ? filename : '附件 #$aid',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface,
                          decoration: inserted
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            '#$aid',
                            style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          if (inserted) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.check_circle_outline,
                              size: 11,
                              color: cs.primary,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '已插入',
                              style: TextStyle(fontSize: 10, color: cs.primary),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // 选中指示
                if (isSelected)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.check_circle,
                      size: 20,
                      color: cs.primary,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
