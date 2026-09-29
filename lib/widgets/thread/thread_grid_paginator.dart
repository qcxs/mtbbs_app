part of 'thread_grid.dart';

/// [ThreadGrid] 的悬浮翻页按钮逻辑。
extension on _ThreadGridState {
  // ==================== 悬浮翻页按钮 ====================

  Widget _buildFloatingPaginator(ThreadListController ctrl, ColorScheme cs) {
    final pageLabel = '第 ${ctrl.page} 页';

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(24),
      color: cs.surface,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pageBtn(
              icon: Icons.chevron_left,
              enabled: ctrl.hasPrev,
              onTap: () {
                ctrl.prevPage();
                _handlePageChange();
              },
              cs: cs,
            ),
            Container(width: 1, height: 20, color: cs.outlineVariant),
            GestureDetector(
              onTap: () => _showPagePicker(ctrl),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: ctrl.state == LoadState.loading
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.onSurfaceVariant,
                        ),
                      )
                    : Text(
                        pageLabel,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
            ),
            Container(width: 1, height: 20, color: cs.outlineVariant),
            _pageBtn(
              icon: Icons.chevron_right,
              enabled: ctrl.hasNext,
              onTap: () {
                ctrl.nextPage();
                _handlePageChange();
              },
              cs: cs,
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageBtn({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
    required ColorScheme cs,
  }) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        icon: Icon(icon, size: 20),
        onPressed: enabled ? onTap : null,
        color: enabled ? cs.onSurfaceVariant : cs.outlineVariant,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      ),
    );
  }

  void _showPagePicker(ThreadListController ctrl) {
    showPageJumpDialog(
      context,
      currentPage: ctrl.page,
      totalPages: ctrl.totalPages,
      onGoToPage: (p) {
        ctrl.goToPage(p);
        _handlePageChange();
      },
    );
  }
}
