import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:mtbbs/core/parser/bbcode2html.dart';
import 'package:mtbbs/core/utils/cache_utils.dart';
import 'package:mtbbs/core/app/emoji_loader.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/utils/url_router.dart';
import 'package:mtbbs/config/brand_colors.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/bbcode/bbcode_table.dart';
import 'package:mtbbs/widgets/bbcode/bbcode_code_block.dart';
import 'package:mtbbs/widgets/image_preview/image_preview.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';

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

/// 计算帖子图片显示宽度（px）。
///
/// - 无显式宽：占满可用宽度，但封顶 [maxImageWidth]（宽屏平衡）
/// - 显式宽（[img=W,H]）：尊重作者意图，但 clamp 到可用宽度防溢出
double resolvePostImageWidth({
  double? explicitWidth,
  required double availableWidth,
  required double maxImageWidth,
}) {
  if (explicitWidth != null && explicitWidth > 0) {
    return explicitWidth.clamp(1, availableWidth).toDouble();
  }
  return availableWidth.clamp(1, maxImageWidth).toDouble();
}

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
  final Set<String>? disabledTags;
  final bool autoDetectUrls;

  const PostHtmlWidget({
    super.key,
    required this.bbcode,
    this.fontSize = 16,
    this.disabledTags,
    this.autoDetectUrls = true,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveDisabled =
        disabledTags ??
        context.select<SettingsProvider, Set<String>>(
          (s) => s.disabledBbcodeTags,
        );
    // 宽屏时帖子图片最大宽度（px）
    final maxImageWidth = context.select<SettingsProvider, int>(
      (s) => s.maxImageWidth,
    );

    // 1. 仅按 [table] 分割（code 由 BBCode2Html 还原为占位元素，
    //    flutter_html extension 原地替换为代码高亮组件，不参与分段，
    //    避免切分拆散 hide/quote/free/table 等容器标签）
    final segments = _buildSegments(bbcode);
    final content = segments.length == 1 && segments.first is _HtmlSegment
        ? _buildHtmlSegment(
            context,
            bbcode,
            fontSize,
            effectiveDisabled,
            autoDetectUrls,
            maxImageWidth,
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final segment in segments)
                switch (segment) {
                  _HtmlSegment(:final content) => _buildHtmlSegment(
                    context,
                    content,
                    fontSize,
                    effectiveDisabled,
                    autoDetectUrls,
                    maxImageWidth,
                  ),
                  _TableSegment(:final content) => BbcodeTableWidget(
                    bbcode: content,
                    fontSize: fontSize,
                    disabledTags: effectiveDisabled,
                    autoDetectUrls: autoDetectUrls,
                  ),
                },
            ],
          );
    return SelectionArea(child: content);
  }

  /// 生成渲染段列表：按 [table] 分割
  List<_Segment> _buildSegments(String bbcode) {
    final result = <_Segment>[];
    for (final tableSeg in splitByTable(bbcode)) {
      if (tableSeg.isTable) {
        result.add(_TableSegment(tableSeg.content));
      } else {
        result.add(_HtmlSegment(tableSeg.content));
      }
    }
    return result;
  }

  /// 构建一段纯 HTML/BBCode 渲染（不含表格）
  static Widget _buildHtmlSegment(
    BuildContext context,
    String bbcodeContent,
    double fontSize,
    Set<String> disabledTags,
    bool autoDetectUrls,
    int maxImageWidth,
  ) {
    final cs = Theme.of(context).colorScheme;

    final converter = BBCode2Html(
      // 表情数据由 EmojiService 按站点维护且几乎不变，渲染层直接获取
      emojiMap: EmojiService().map,
      smilieIdMap: EmojiService().smilieIdMap,
      disabledTags: disabledTags,
      baseUrl: SiteStore.instance.baseUrl,
      autoDetectUrls: autoDetectUrls,
      // code/table 还原为占位元素，由下方 extension 原地替换为
      // 高亮组件 / Flutter 原生 Table，保证 hide/quote/free 等容器结构完整
      emitCodePlaceholder: true,
      emitTablePlaceholder: true,
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
        'a': Style(
          color: cs.linkColor,
          textDecoration: TextDecoration.underline,
        ),
        'blockquote': Style(
          backgroundColor: cs.quoteBg,
          margin: Margins.zero,
          padding: HtmlPaddings.only(left: 12, right: 12, top: 8, bottom: 8),
        ),
        'pre': Style(backgroundColor: cs.codeBgColor, margin: Margins.zero),
        'code': Style(color: cs.codeTextColor, fontFamily: 'monospace'),
        '.bbcode-free': Style(
          backgroundColor: cs.quoteBg,
          margin: Margins.zero,
          padding: HtmlPaddings.all(8),
        ),
        '.bbcode-attach': Style(
          backgroundColor: cs.attachBgColor,
          margin: Margins.zero,
          padding: HtmlPaddings.all(8),
        ),
        '.bbcode-locked': Style(
          backgroundColor: cs.quoteBg,
          margin: Margins.zero,
          padding: HtmlPaddings.only(left: 12, right: 12, top: 8, bottom: 8),
        ),
        '.bbcode-pstatus': Style(
          fontSize: FontSize(12),
          margin: Margins.zero,
          // 居中
          textAlign: TextAlign.center,
          padding: HtmlPaddings.zero,
        ),
        '.bbcode-reward': Style(
          backgroundColor: cs.quoteBg,
          margin: Margins.zero,
          padding: HtmlPaddings.only(left: 12, right: 12, top: 8, bottom: 8),
        ),
        '.bbcode-poll': Style(margin: Margins.zero, padding: HtmlPaddings.zero),
        'ul': Style(margin: Margins.zero, padding: HtmlPaddings.only(left: 24)),
        'ol': Style(margin: Margins.zero, padding: HtmlPaddings.only(left: 24)),
        // 让嵌套的list不缩进
        'ul ul': Style(padding: HtmlPaddings.zero),
        'ol ol': Style(padding: HtmlPaddings.zero),
        'ul ol': Style(padding: HtmlPaddings.zero),
        'ol ul': Style(padding: HtmlPaddings.zero),
        'li': Style(margin: Margins.zero, padding: HtmlPaddings.zero),
        'hr': Style(
          height: Height(1),
          backgroundColor: cs.outlineVariant,
          border: Border(),
          margin: Margins.symmetric(vertical: 8),
          padding: HtmlPaddings.zero,
        ),
      },
      extensions: [
        ImageExtension(
          builder: (ctx) {
            final src = ctx.attributes['src'] ?? '';
            if (src.isEmpty) return const SizedBox.shrink();
            // 通过 data-type="emoji" 区分表情图片和普通帖子图片
            final isEmoji = ctx.attributes['data-type'] == 'emoji';
            final cacheManager = isEmoji
                ? emojiCacheManager
                : imageCacheManager;

            // 表情：固定行内尺寸
            if (isEmoji) {
              return CachedNetworkImage(
                imageUrl: src,
                cacheManager: cacheManager,
                width: 20,
                height: 20,
                fit: BoxFit.contain,
                errorWidget: (_, __, ___) => Icon(
                  Icons.emoji_emotions_outlined,
                  size: 18,
                  color: cs.outline,
                ),
              );
            }

            // 显式宽度（[img=W,H] 或 HTML 自带 width）
            final explicitW = double.tryParse(ctx.attributes['width'] ?? '');
            // 普通帖子图片：窄屏占满可用宽度，宽屏封顶 maxImageWidth；
            // [img=W,H] 尊重作者显式宽度，但 clamp 到可用宽度防溢出。
            return LayoutBuilder(
              builder: (context, constraints) {
                final available = constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : MediaQuery.sizeOf(context).width;
                final width = resolvePostImageWidth(
                  explicitWidth: explicitW,
                  availableWidth: available,
                  maxImageWidth: maxImageWidth.toDouble(),
                );
                return GestureDetector(
                  onLongPress: () => showImageActions(
                    context,
                    imageUrls: [src],
                    sourceInfo: '帖子图片',
                  ),
                  child: CachedNetworkImage(
                    imageUrl: src,
                    cacheManager: cacheManager,
                    width: width,
                    memCacheWidth: (width * 2).toInt(),
                    fit: BoxFit.contain,
                    placeholder: (_, __) => SizedBox(
                      width: width,
                      height: 100,
                      child: const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Icon(
                      Icons.broken_image_outlined,
                      size: 48,
                      color: cs.outline,
                    ),
                  ),
                );
              },
            );
          },
        ),
        BbcodeCodeExtension(
          codeBlocks: converter.codeBlocks,
          fontSize: fontSize,
        ),
        BbcodeTableExtension(
          tableBlocks: converter.tableBlocks,
          fontSize: fontSize,
          disabledTags: disabledTags,
          autoDetectUrls: autoDetectUrls,
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
            showToast('已复制', duration: const Duration(seconds: 1));
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
          showToast('已复制', duration: const Duration(seconds: 1));
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
          context.push(
            '/browser?url=${Uri.encodeComponent(url)}&intercept=false',
          );
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
