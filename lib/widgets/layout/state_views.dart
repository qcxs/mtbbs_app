import 'package:flutter/material.dart';

/// 全页加载指示
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.strokeWidth = 2});

  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CircularProgressIndicator(strokeWidth: strokeWidth),
    );
  }
}

/// 空状态视图
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
