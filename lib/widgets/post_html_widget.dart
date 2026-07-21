import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_html/flutter_html.dart';
import '../core/bbcode2html.dart';
import '../core/emoji_loader.dart';
import '../core/url_router.dart';
import '../config/site_config.dart';
import '../providers/settings_provider.dart';
import 'bbcode_table.dart';
import 'bbcode_code_block.dart';
import 'image_preview/image_preview.dart';

/// 渲染段类型
sealed class _Segment {}

class _HtmlSegment extends _Segment {
  final String content;
  _HtmlSegment(this.content);
}

class _TableSegment extends _Segment {
  final String content;
  _TableSegment(this.content);
}

class _CodeSegment extends _Segment {
  final String content;
  _CodeSegment(this.content);
}

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
    final settings = context.watch<SettingsProvider>();
    final effectiveDisabled = disabledTags ?? settings.disabledBbcodeTags;

    // 1. 先按 [code] 分割，再对非 code 段按 [table] 分割
    final segments = _buildSegments(bbcode);
    if (segments.length == 1 && segments.first is _HtmlSegment) {
      // 无 code 也无 table：保持原有路径（单个 Html widget）
      return _buildHtmlSegment(
        context,
        bbcode,
        fontSize,
        emojiMap,
        smilieIdMap,
        effectiveDisabled,
        autoDetectUrls,
      );
    }

    // 有 code/table 时分段渲染
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final segment in segments)
          switch (segment) {
            _HtmlSegment(:final content) => _buildHtmlSegment(
              context,
              content,
              fontSize,
              emojiMap,
              smilieIdMap,
              effectiveDisabled,
              autoDetectUrls,
            ),
            _TableSegment(:final content) => BbcodeTableWidget(
              bbcode: content,
              fontSize: fontSize,
              emojiMap: emojiMap,
              smilieIdMap: smilieIdMap ?? EmojiService().smilieIdMap,
              disabledTags: effectiveDisabled,
              autoDetectUrls: autoDetectUrls,
            ),
            _CodeSegment(:final content) => BbcodeCodeBlock(
              code: content,
              fontSize: fontSize.clamp(11, 16).toDouble(),
            ),
          },
      ],
    );
  }

  /// 生成渲染段列表：先按 [code] 分割，再对非 code 段按 [table] 分割
  List<_Segment> _buildSegments(String bbcode) {
    final result = <_Segment>[];
    for (final codeSeg in splitByCode(bbcode)) {
      if (codeSeg.isCode) {
        result.add(_CodeSegment(codeSeg.content));
      } else {
        // 非 code 段，按 [table] 进一步分割
        for (final tableSeg in splitByTable(codeSeg.content)) {
          if (tableSeg.isTable) {
            result.add(_TableSegment(tableSeg.content));
          } else {
            result.add(_HtmlSegment(tableSeg.content));
          }
        }
      }
    }
    return result;
  }

  /// 构建一段纯 HTML/BBCode 渲染（不含表格）
  static Widget _buildHtmlSegment(
    BuildContext context,
    String bbcodeContent,
    double fontSize,
    Map<String, String>? emojiMap,
    Map<String, String>? smilieIdMap,
    Set<String> disabledTags,
    bool autoDetectUrls,
  ) {
    final converter = BBCode2Html(
      emojiMap: emojiMap,
      smilieIdMap: smilieIdMap,
      disabledTags: disabledTags,
      baseUrl: SiteConfig.baseUrl,
      autoDetectUrls: autoDetectUrls,
    );
    final html = converter.convert(bbcodeContent);
    return Html(
      data: html,
      style: {
        'body': Style(
          fontSize: FontSize(fontSize),
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
        ),
        'blockquote': Style(
          backgroundColor: const Color(0xFFFFF8E1),
          margin: Margins.zero,
          padding: HtmlPaddings.only(left: 12, top: 8, bottom: 8),
        ),
        'pre': Style(
          backgroundColor: const Color(0xFF1E1E1E),
          margin: Margins.zero,
        ),
        'code': Style(color: const Color(0xFF98C379), fontFamily: 'monospace'),
        '.bbcode-hide': Style(
          backgroundColor: const Color(0xFFFFF8E1),
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
        ),
        '.bbcode-free': Style(
          backgroundColor: const Color(0xFFF0FFF0),
          margin: Margins.zero,
          padding: HtmlPaddings.all(8),
        ),
        '.bbcode-attach': Style(
          backgroundColor: const Color(0xFFE3F2FD),
          margin: Margins.zero,
          padding: HtmlPaddings.all(8),
        ),
        'ul': Style(margin: Margins.zero, padding: HtmlPaddings.zero),
        'ol': Style(margin: Margins.zero, padding: HtmlPaddings.zero),
        'li': Style(margin: Margins.zero, padding: HtmlPaddings.zero),
        'hr': Style(
          height: Height(1),
          backgroundColor: Colors.grey.shade300,
          border: Border(),
          margin: Margins.symmetric(vertical: 8),
          padding: HtmlPaddings.zero,
        ),
        'a': Style(
          color: const Color(0xFF336699),
          textDecoration: TextDecoration.underline,
        ),
      },
      extensions: [
        ImageExtension(
          builder: (ctx) {
            final src = ctx.attributes['src'] ?? '';
            if (src.isEmpty) return const SizedBox.shrink();
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
      onLinkTap: (link, attributes, element) {
        if (link != null && link.isNotEmpty) {
          _handleLinkTap(context, link);
        }
      },
    );
  }

  static void _handleLinkTap(BuildContext context, String url) {
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

  static Future<void> _showActionDialog(
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
  static Future<void> _showUrlEditDialog(
    BuildContext context,
    String url,
  ) async {
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
          context.push('/browser?url=${Uri.encodeComponent(url)}&intercept=false');
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
      constraints: const BoxConstraints(maxWidth: 360, maxHeight: 280),
      title: Row(
        children: [
          const Expanded(child: Text('链接', style: TextStyle(fontSize: 16))),
          IconButton(
            icon: const Icon(Icons.open_in_browser, size: 20),
            tooltip: '外部打开',
            onPressed: () => Navigator.of(context).pop('__external__'),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: SelectableText(url, style: const TextStyle(fontSize: 12)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop('__app__'),
          child: const Text('打开'),
        ),
      ],
    );
  }
}
