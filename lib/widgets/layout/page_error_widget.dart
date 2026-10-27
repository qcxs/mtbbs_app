import 'package:flutter/material.dart';

/// 统一页面错误组件
///
/// 在 API 页面加载失败时展示错误信息，支持重试和返回操作。
/// 使用方式：
/// ```dart
/// if (_error != null) {
///   return PageErrorWidget(
///     message: _error!,
///     onRetry: () => _fetch(),
///   );
/// }
/// ```
class PageErrorWidget extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  /// 是否显示"返回"按钮（默认显示，内嵌页面可关闭）
  final bool showBack;

  /// 额外操作按钮（如"查看缓存"），追加在重试/返回之前
  final List<Widget> extraActions;

  const PageErrorWidget({
    super.key,
    required this.message,
    this.onRetry,
    this.showBack = true,
    this.extraActions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                ...extraActions,
                if (onRetry != null)
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('重试'),
                  ),
                if (showBack)
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('返回'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
