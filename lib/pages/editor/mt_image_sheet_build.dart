part of 'mt_image_sheet.dart';

/// MT 图床底部抽屉 — 构建相关 UI 方法。
extension on _MtImageSheetState {
  Widget _buildPage(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _dragHandle(),
          _titleBar(),
          const Divider(height: 1),
          _toolBar(),
          const Divider(height: 1),
          Expanded(child: _buildContent(scrollCtrl)),
        ],
      ),
    );
  }

  Widget _dragHandle() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
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
    );
  }

  Widget _titleBar() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Row(
        children: [
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'MT 图床',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          if (_authenticating)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (_authStatus != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                _authStatus!,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _toolBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
      child: Row(
        children: [
          _toolBtn(
            Icons.add_photo_alternate_outlined,
            '选择图片',
            false,
            _pickFiles,
          ),
          if (_authenticating)
            _toolBtn(Icons.refresh, '重试验证', false, _retryAuth),
          if (_queue.isNotEmpty && !_uploading && !_authenticating)
            _toolBtn(Icons.cloud_upload_outlined, '上传队列', false, _processQueue),
          const Spacer(),
          if (_selectedIndex != null) ...[
            _toolBtn(Icons.visibility_outlined, '查看', false, _viewSelected),
            const SizedBox(width: 8),
            _toolBtn(
              Icons.add_photo_alternate_outlined,
              '插入',
              false,
              _insertSelected,
            ),
          ],
        ],
      ),
    );
  }

  void _viewSelected() {
    if (_selectedIndex == null || _selectedIndex! >= _history.length) return;
    final item = _history[_selectedIndex!];
    context.push(
      '/image-viewer',
      extra: {
        'urls': [item.url],
        'index': 0,
      },
    );
  }

  void _insertSelected() {
    if (_selectedIndex == null || _selectedIndex! >= _history.length) return;
    widget.onInsert(_history[_selectedIndex!].bbcode);
    Navigator.of(context).pop();
  }

  Widget _buildContent(ScrollController scrollCtrl) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      controller: scrollCtrl,
      children: [
        if (_authenticating &&
            _authStatus != null &&
            !_authStatus!.contains('验证中'))
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 40,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(height: 8),
                  Text(_authStatus!, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ),
        if (_queue.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              '待上传 (${_queue.length})',
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...List.generate(_queue.length, (i) {
            final item = _queue[i];
            final isCurrent = _uploading && i == _uploadingIndex;
            return ListTile(
              dense: true,
              leading: Icon(
                isCurrent ? Icons.cloud_upload : Icons.image_outlined,
                size: 20,
                color: isCurrent ? cs.onSurfaceVariant : null,
              ),
              title: Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
              subtitle: isCurrent
                  ? LinearProgressIndicator(value: _currentProgress)
                  : Text(
                      formatBytes(item.size),
                      style: const TextStyle(fontSize: 12),
                    ),
              trailing: _uploading
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => _removeFromQueue(i),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
            );
          }),
          const Divider(),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Icon(Icons.history, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '历史上传',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton.icon(
                // 管理面板同样是底部面板：先关掉当前面板，避免两层叠加
                onPressed: () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  showMtImageManageSheet(nav.context);
                },
                icon: const Icon(Icons.settings, size: 16),
                label: const Text('管理', style: TextStyle(fontSize: 13)),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
        if (_loadingHistory)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_history.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                '暂无历史记录',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
          )
        else
          ...List.generate(_history.length, (i) {
            final item = _history[i];
            final isSelected = _selectedIndex == i;
            return ListTile(
              dense: true,
              selected: isSelected,
              selectedTileColor: cs.onSurfaceVariant.withValues(alpha: 0.08),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: CachedNetworkImage(
                  imageUrl: item.thumbnailUrl.isNotEmpty
                      ? item.thumbnailUrl
                      : item.url,
                  cacheManager: imageCacheManager,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    width: 44,
                    height: 44,
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
                style: const TextStyle(fontSize: 14),
              ),
              subtitle: Text(
                '${item.sizeText}  ·  ${formatRelativeTimeShort(item.uploadedAt)}',
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () =>
                  _setState(() => _selectedIndex = isSelected ? null : i),
            );
          }),
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
                Icon(
                  icon,
                  size: 20,
                  color: disabled ? cs.onSurfaceVariant : null,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: disabled ? cs.onSurfaceVariant : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
