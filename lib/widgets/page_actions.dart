import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// 通用页面顶部操作组件
/// ```dart
/// AppBar(
///   actions: [
///     PageActions(
///       url: _pageUrl,
///       onRefresh: () => _fetch(page: 1),
///       loading: _loading,
///     ),
///   ],
/// )
/// ```
class PageActions extends StatelessWidget {
  /// 当前页面 URL，用于"在浏览器打开"和"复制链接"
  final String url;

  /// 刷新回调，为 null 时不显示刷新按钮
  final VoidCallback? onRefresh;

  /// 加载中，为 true 时禁用刷新按钮
  final bool? loading;

  /// 复制链接时的提示文字，如"复制帖子链接"、"复制个人主页链接"
  final String? copyLabel;

  /// 额外的菜单项，追加到默认菜单（在浏览器打开/复制链接）之后
  final List<PopupMenuEntry<String>>? extraItems;

  /// 额外菜单项选中回调
  final void Function(String)? onExtraSelected;

  const PageActions({
    super.key,
    required this.url,
    this.onRefresh,
    this.loading,
    this.copyLabel,
    this.extraItems,
    this.onExtraSelected,
  });

  void _openInBrowser(BuildContext context) {
    context.push('/browser?url=${Uri.encodeComponent(url)}');
  }

  void _copyLink(BuildContext context) {
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(copyLabel ?? '链接已复制'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onRefresh != null)
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: '刷新',
            onPressed: (loading == true) ? null : onRefresh,
          ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 20),
          padding: EdgeInsets.zero,
          onSelected: (value) {
            switch (value) {
              case '_openBrowser':
                _openInBrowser(context);
              case '_copyLink':
                _copyLink(context);
              default:
                onExtraSelected?.call(value);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: '_openBrowser', child: Text('在浏览器中打开')),
            PopupMenuItem(value: '_copyLink', child: Text(copyLabel ?? '复制链接')),
            if (extraItems != null && extraItems!.isNotEmpty) ...[
              const PopupMenuDivider(),
              ...extraItems!,
            ],
          ],
        ),
      ],
    );
  }
}
