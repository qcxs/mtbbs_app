import 'package:flutter/material.dart';

/// 加载更多列表的底部状态条
///
/// [loading] 为 true 时显示加载中转圈；[hasMore] 为 false 时显示 [endText]
/// （默认「没有更多了」）；其余情况不占空间。
class LoadMoreFooter extends StatelessWidget {
  final bool loading;
  final bool hasMore;
  final String endText;

  const LoadMoreFooter({
    super.key,
    required this.loading,
    required this.hasMore,
    this.endText = '没有更多了',
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (!hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text(
            endText,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
