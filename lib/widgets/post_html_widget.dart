import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_html/flutter_html.dart';
import '../core/bbcode2html.dart';
import '../core/url_router.dart';
import '../config/site_config.dart';
import 'image_preview/image_preview.dart';

/// 可被全局/局部禁用的 BBCode 样式标签（从旧 PostAstWidget 迁移）
const bbcodeStyleTags = <String>{
  'bold',
  'italic',
  'underline',
  'strikethrough',
  'color',
  'size',
  'font',
  'backcolor',
  'imgDimension',
  'link',
  'email',
  'qq',
};

/// 基于 flutter_html 的 BBCode 渲染组件
///
/// 将 BBCode 转换为 HTML，由 flutter_html 渲染为 Flutter Widget。
/// 替代旧的 PostAstWidget（AST → Widget 方案）。
///
/// 支持：
/// - 所有标准 BBCode 格式
/// - [url] 链接（点击弹出确认对话框）
/// - 表情渲染
/// - 标签禁用
/// - 图片长按查看（点击穿透给父级链接）
class PostHtmlWidget extends StatelessWidget {
  final String bbcode;
  final double fontSize;
  final Map<String, String>? emojiMap;
  final Map<String, String>? smilieIdMap;
  final Set<String>? disabledTags;
  final bool autoDetectUrls;

  const PostHtmlWidget({
    super.key,
    required this.bbcode,
    this.fontSize = 16,
    this.emojiMap,
    this.smilieIdMap,
    this.disabledTags,
    this.autoDetectUrls = true,
  });

  @override
  Widget build(BuildContext context) {
    // 1. BBCode → HTML
    final converter = BBCode2Html(
      emojiMap: emojiMap,
      smilieIdMap: smilieIdMap,
      disabledTags: disabledTags,
      baseUrl: SiteConfig.baseUrl,
      autoDetectUrls: autoDetectUrls,
    );
    final html = converter.convert(bbcode);

    // 2. 使用 flutter_html 渲染
    return Html(
      data: html,
      style: {
        // 全局基础样式
        'body': Style(
          fontSize: FontSize(fontSize),
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
        ),
        // 引用块 - 移除默认margin/padding避免背景空白
        'blockquote': Style(
          backgroundColor: const Color(0xFFFFF8E1),
          margin: Margins.zero,
          padding: HtmlPaddings.only(left: 12, top: 8, bottom: 8),
        ),
        // 代码块
        'pre': Style(
          backgroundColor: const Color(0xFF1E1E1E),
          margin: Margins.zero,
        ),
        'code': Style(color: const Color(0xFF98C379), fontFamily: 'monospace'),
        // 隐藏内容
        '.bbcode-hide': Style(
          backgroundColor: const Color(0xFFFFF8E1),
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
        ),
        // 免费信息 - 移除默认margin避免背景空白
        '.bbcode-free': Style(
          backgroundColor: const Color(0xFFF0FFF0),
          margin: Margins.zero,
          padding: HtmlPaddings.all(8),
        ),
        // 附件
        '.bbcode-attach': Style(
          backgroundColor: const Color(0xFFE3F2FD),
          margin: Margins.zero,
          padding: HtmlPaddings.all(8),
        ),
        // 列表 - 移除默认padding避免缩进累加
        'ul': Style(margin: Margins.zero, padding: HtmlPaddings.zero),
        'ol': Style(margin: Margins.zero, padding: HtmlPaddings.zero),
        'li': Style(margin: Margins.zero, padding: HtmlPaddings.zero),
        // 分割线 — flutter_html 默认用 Border.all() 导致高度异常
        'hr': Style(
          height: Height(1),
          backgroundColor: Colors.grey.shade300,
          border: Border(),
          margin: Margins.symmetric(vertical: 8),
          padding: HtmlPaddings.zero,
        ),
        // 链接
        'a': Style(
          color: const Color(0xFF336699),
          textDecoration: TextDecoration.underline,
        ),
      },
      // 图片长按查看（点击不消费事件，穿透给父级链接）
      extensions: [
        ImageExtension(
          builder: (ctx) {
            final src = ctx.attributes['src'] ?? '';
            if (src.isEmpty) return const SizedBox.shrink();

            // 优先使用 width 属性（普通图片），否则解析 style 中的 height（表情）
            final w = ctx.attributes['width'];
            final width = w != null ? double.tryParse(w) : null;
            double? height;
            if (width == null) {
              final hAttr = ctx.attributes['height'];
              if (hAttr != null && hAttr.isNotEmpty) {
                height = double.tryParse(hAttr);
              }
              if (height == null) {
                final style = ctx.attributes['style'] ?? '';
                final hMatch = RegExp(r'height\s*:\s*(\d+)').firstMatch(style);
                if (hMatch != null) {
                  height = double.tryParse(hMatch.group(1)!);
                }
              }
            }

            return GestureDetector(
              onLongPress: () => showImageActions(
                context,
                imageUrls: [src],
                sourceInfo: '帖子图片',
              ),
              child: Image.network(
                src,
                width: width,
                height: height,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            );
          },
        ),
      ],
      // 链接点击
      onLinkTap: (link, attributes, element) {
        if (link != null && link.isNotEmpty) {
          _handleLinkTap(context, link);
        }
      },
    );
  }

  void _handleLinkTap(BuildContext context, String url) {
    // QQ 链接特殊处理
    if (url.contains('wpa.qq.com')) {
      final qqMatch = RegExp(r'uin=(\d+)').firstMatch(url);
      if (qqMatch != null) {
        _showActionDialog(
          context,
          title: 'QQ',
          message: 'QQ号:\n${qqMatch.group(1)}',
          actionLabel: '复制',
          copyValue: qqMatch.group(1)!,
          onAction: () {
            Clipboard.setData(ClipboardData(text: qqMatch.group(1)!));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('已复制'),
                duration: Duration(seconds: 1),
              ),
            );
          },
        );
        return;
      }
    }

    // mailto 链接
    if (url.startsWith('mailto:')) {
      _showActionDialog(
        context,
        title: '发送邮件',
        message: '发送至:\n${url.substring(7)}',
        actionLabel: '发送',
        copyValue: url.substring(7),
        onAction: () {
          final uri = Uri.tryParse(url);
          if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
        },
      );
      return;
    }

    // 普通链接 — 可编辑弹窗
    _showUrlEditDialog(context, url);
  }

  Future<void> _showActionDialog(
    BuildContext context, {
    required String title,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
    required String copyValue,
  }) async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 360),
        title: Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.of(ctx).pop(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        content: SelectableText(message, style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('copy'),
            child: const Text('复制'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('action'),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    switch (result) {
      case 'action':
        onAction();
      case 'copy':
        await Clipboard.setData(ClipboardData(text: copyValue));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('已复制'),
              duration: Duration(seconds: 1),
            ),
          );
        }
    }
  }

  /// 链接确认弹窗 — App打开（路由匹配）/ 外部浏览器 / 取消
  Future<void> _showUrlEditDialog(BuildContext context, String url) async {
    final action = await showDialog<String>(
      context: context,
      builder: (_) => _UrlActionDialog(url: url),
    );
    if (action == null || context.mounted == false) return;

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return;

    switch (action) {
      case '__app__':
        final routeResult = UrlRouter.parse(url);
        if (routeResult.appPath != null) {
          context.push(routeResult.appPath!);
        } else {
          context.push('/browser?url=${Uri.encodeComponent(url)}');
        }
      case '__external__':
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

/// 链接操作确认弹窗
class _UrlActionDialog extends StatelessWidget {
  final String url;
  const _UrlActionDialog({required this.url});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      constraints: const BoxConstraints(maxWidth: 360),
      title: Row(
        children: [
          const Expanded(child: Text('链接', style: TextStyle(fontSize: 16))),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
      content: SelectableText(url, style: const TextStyle(fontSize: 12)),
      actionsOverflowAlignment: OverflowBarAlignment.start,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop('__external__'),
          child: const Text('外部打开'),
        ),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop('__app__'),
          child: const Text('App打开'),
        ),
      ],
    );
  }
}
