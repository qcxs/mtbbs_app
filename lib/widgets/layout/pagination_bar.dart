import 'package:flutter/material.dart';
import 'package:mtbbs/widgets/dialog/page_jump_dialog.dart';

/// 通用分页栏：上一页 / 页码指示（点击弹出跳页对话框）/ 下一页
///
/// 只渲染按钮行，不包含外层容器；调用方可直接使用或放入自己的容器/行中
/// （如作为底部条、或嵌入头部行）。
class PaginationBar extends StatelessWidget {
  final int page;
  final int totalPages;
  final ValueChanged<int> onGoToPage;

  const PaginationBar({
    super.key,
    required this.page,
    required this.totalPages,
    required this.onGoToPage,
  });

  void _showPicker(BuildContext context) {
    showPageJumpDialog(
      context,
      currentPage: page,
      totalPages: totalPages,
      onGoToPage: onGoToPage,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, size: 20),
          onPressed: page > 1 ? () => onGoToPage(page - 1) : null,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
          tooltip: '上一页',
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: () => _showPicker(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$page / $totalPages',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.chevron_right, size: 20),
          onPressed: page < totalPages ? () => onGoToPage(page + 1) : null,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
          tooltip: '下一页',
        ),
      ],
    );
  }
}
