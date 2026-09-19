import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:go_router/go_router.dart';
import 'package:html/dom.dart' as dom;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mtbbs/config/brand_colors.dart';
import 'package:mtbbs/core/app/emoji_loader.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/parser/bbcode2html.dart';
import 'package:mtbbs/core/utils/cache_utils.dart';
import 'package:mtbbs/core/utils/url_router.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/bbcode/bbcode_code_block.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';
import 'package:mtbbs/widgets/image_preview/image_preview.dart';

/// 可被全局/局部禁用的 BBCode 样式标签
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

/// 计算帖子图片的**宽度上限**（px）。
///
/// - 无显式宽：占满可用宽度，但封顶 [maxImageWidth]（宽屏平衡）；
///   实际渲染宽度还会被图片原始像素进一步收窄，见 [BbcodeImage]
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

/// 基于 flutter_widget_from_html 的 BBCode 渲染组件
///
/// 链路：`BBCode → BBCode2Html → HTML → HtmlWidget`
///
/// 依赖 flutter_widget_from_html 的两项能力（flutter_html 均缺失）：
/// 1. **原生 `<table>`** — 用其自研 [HtmlTable] 渲染，支持 colspan/rowspan、
///    列超宽可滚动，不再需要「占位元素 + 按 table 分段」那套绕行方案
/// 2. **内联 / 块级注入分离** — [customWidgetBuilder] 返回 [InlineCustomWidget]
///    即内联，返回普通 Widget 即块级。因此表情内联、帖子图片块级可以
///    在同一段落流里共存，且链接手势会下沉包裹内部块级元素，
///    点击图片能正常冒泡到 `[url]` 的点击事件
///
/// 支持：所有标准 BBCode 格式、链接点击弹窗、表情、标签禁用、图片长按菜单。
class PostHtmlWidget extends StatelessWidget {
  final String bbcode;

  /// 正文字号（px）。为 null 时跟随设置项「正文字号」（`SettingsProvider.fontSize`）；
  /// 显式传入则覆盖（列表内回复预览、个人签名等次要位置用更小字号）
  final double? fontSize;
  final Set<String>? disabledTags;
  final bool autoDetectUrls;

  const PostHtmlWidget({
    super.key,
    required this.bbcode,
    this.fontSize,
    this.disabledTags,
    this.autoDetectUrls = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveDisabled =
        disabledTags ??
        context.select<SettingsProvider, Set<String>>(
          (s) => s.disabledBbcodeTags,
        );
    final maxImageWidth = context.select<SettingsProvider, int>(
      (s) => s.maxImageWidth,
    );
    // 正文字号：显式值优先，否则跟随设置项（与 disabledTags 同一套"可覆盖"约定）
    final textSize =
        fontSize ?? context.select<SettingsProvider, double>((s) => s.fontSize);

    final converter = BBCode2Html(
      // 表情数据由 EmojiService 按站点维护且几乎不变，渲染层直接获取
      emojiMap: EmojiService().map,
      smilieIdMap: EmojiService().smilieIdMap,
      disabledTags: effectiveDisabled,
      baseUrl: SiteStore.instance.baseUrl,
      autoDetectUrls: autoDetectUrls,
      // [code] 还原为占位元素，由 customWidgetBuilder 原地替换为高亮组件
      emitCodePlaceholder: true,
    );
    final html = converter.convert(bbcode);
    final codeBlocks = converter.codeBlocks;

    return SelectionArea(
      child: HtmlWidget(
        html,
        // 关闭异步构建：帖子正文需要与滚动同步构建，且便于测试确定性
        buildAsync: false,
        textStyle: TextStyle(fontSize: textSize, color: cs.onSurface),
        customStylesBuilder: (element) => _stylesFor(element, cs),
        customWidgetBuilder: (element) {
          // [code] 占位 div → 代码高亮组件（块级）
          final codeIndex = element.attributes['data-code-index'];
          if (codeIndex != null) {
            final i = int.tryParse(codeIndex) ?? -1;
            if (i < 0 || i >= codeBlocks.length) return const SizedBox.shrink();
            return BbcodeCodeBlock(
              code: codeBlocks[i],
              // 代码块跟随正文字号，上限同步设置项上限（曾封顶 16，字号调大后代码块不跟）
              fontSize: textSize.clamp(11, 32).toDouble(),
            );
          }
          // img → 表情内联 / 帖子图片块级
          if (element.localName == 'img') {
            final src = element.attributes['src'] ?? '';
            if (src.isEmpty) return const SizedBox.shrink();
            if (element.attributes['data-type'] == 'emoji') {
              return InlineCustomWidget(
                alignment: PlaceholderAlignment.middle,
                child: _EmojiImage(url: src),
              );
            }
            return BbcodeImage(
              url: src,
              explicitWidth: double.tryParse(element.attributes['width'] ?? ''),
              maxImageWidth: maxImageWidth.toDouble(),
            );
          }
          return null;
        },
        onTapUrl: (url) {
          _handleLinkTap(context, url);
          return true;
        },
      ),
    );
  }
}

/// Color → CSS 颜色串（`#rrggbbaa`，flutter_widget_from_html 按 CSS 规范解析）
String _cssColor(Color c) {
  final argb = c.toARGB32();
  final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  final alpha = ((argb >> 24) & 0xFF).toRadixString(16).padLeft(2, '0');
  return '#$rgb$alpha';
}

/// BBCode 各容器/元素的主题样式（对应 flutter_html 时代的 `style` map）
///
/// 列表（`[list]`）在转换层已展开为带前缀的普通段落，不产生 `ul/ol/li`。
Map<String, String>? _stylesFor(dom.Element element, ColorScheme cs) {
  final classes = element.classes;

  // 容器类（由 BBCode2Html 输出的 class 决定）
  if (classes.contains('bbcode-free')) {
    return {'background-color': _cssColor(cs.quoteBg), 'padding': '8px'};
  }
  if (classes.contains('bbcode-attach')) {
    return {
      'background-color': _cssColor(cs.attachBgColor),
      'padding': '8px 12px',
      'border-radius': '6px',
    };
  }
  if (classes.contains('bbcode-locked')) {
    return {
      'background-color': _cssColor(cs.lockedBgColor),
      'padding': '8px 12px',
    };
  }
  if (classes.contains('bbcode-reward')) {
    return {'background-color': _cssColor(cs.quoteBg), 'padding': '8px 12px'};
  }
  if (classes.contains('bbcode-pstatus')) {
    return {
      'font-size': '12px',
      'text-align': 'center',
      'color': _cssColor(cs.pstatusTextColor),
    };
  }

  switch (element.localName) {
    case 'a':
      return {'color': _cssColor(cs.linkColor), 'text-decoration': 'underline'};
    case 'blockquote':
      return {
        'background-color': _cssColor(cs.quoteBg),
        'padding': '8px 12px',
        'margin': '0',
      };
    case 'table':
      return {
        'border': '1px solid ${_cssColor(cs.outlineVariant)}',
        'margin': '0',
        'padding': '0',
      };
    case 'td':
      // 不设 text-align：单元格内 [align] 已被 BBCode2Html 转成
      // `<div style="text-align:...">`，由内层元素自行对齐
      return {
        'border': '1px solid ${_cssColor(cs.outlineVariant)}',
        'padding': '4px 8px',
      };
    case 'hr':
      return {
        'height': '1px',
        'background-color': _cssColor(cs.outlineVariant),
        'margin': '8px 0',
      };
  }
  return null;
}

/// 内联表情图片（跟随文字基线行走）
class _EmojiImage extends StatelessWidget {
  final String url;
  const _EmojiImage({required this.url});

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      cacheManager: emojiCacheManager,
      width: 20,
      height: 20,
      fit: BoxFit.contain,
      errorWidget: (_, __, ___) => Icon(
        Icons.emoji_emotions_outlined,
        size: 18,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}

/// 帖子正文图片（块级，独占一行）
///
/// 不挂 `onTap`：点击需冒泡给外层 `[url]` 链接，挂 tap 会消费掉。
/// 只提供长按菜单（查看大图 / 保存）。
///
/// 宽度策略：
/// - 显式尺寸（`[img=W,H]`）→ 强制该宽度（同 HTML `<img width>`，可放大）
/// - 未指定尺寸 → 只约束上限，实际宽度由图片原始像素决定：低分辨率小图
///   **不放大**（放大只会更糊），高分辨率大图仍按可用宽 / 封顶宽收缩
class BbcodeImage extends StatelessWidget {
  final String url;
  final double? explicitWidth;
  final double maxImageWidth;

  const BbcodeImage({
    super.key,
    required this.url,
    this.explicitWidth,
    this.maxImageWidth = 600,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final width = resolvePostImageWidth(
          explicitWidth: explicitWidth,
          availableWidth: available,
          maxImageWidth: maxImageWidth,
        );
        // 未指定尺寸时只给宽度上限、不传 width：渲染器对块级自定义组件下发的是
        // 松约束，图片会按解码后的原始像素测量。解码链路（memCacheWidth →
        // ResizeImage）与缓存层的磁盘缩放都是 allowUpscaling=false，解码结果
        // 不会超过原图，因此"只设上限"即等价于 min(上限, 原始像素宽)。
        final hasExplicitWidth = explicitWidth != null && explicitWidth! > 0;
        final image = CachedNetworkImage(
          imageUrl: url,
          cacheManager: imageCacheManager,
          // 显式尺寸才给 width：给了就会把低分辨率小图拉伸放大（变糊）
          width: hasExplicitWidth ? width : null,
          memCacheWidth: (width * 2).toInt(),
          fit: BoxFit.contain,
          placeholder: (_, __) => const SizedBox(
            height: 100,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          errorWidget: (_, __, ___) =>
              Icon(Icons.broken_image_outlined, size: 48, color: cs.outline),
        );
        return GestureDetector(
          onLongPress: () =>
              showImageActions(context, imageUrls: [url], sourceInfo: '帖子图片'),
          // 显式尺寸：固定盒宽，加载中/加载失败也保持占位宽度，避免状态切换跳动
          // 未指定尺寸：上限盒宽，加载中按上限占位，解码后收敛到原始像素宽
          child: hasExplicitWidth
              ? SizedBox(width: width, child: image)
              : ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: width),
                  child: image,
                ),
        );
      },
    );
  }
}

/// 链接点击处理 — QQ / 邮件 / 普通链接
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
        showToast('已复制', duration: const Duration(seconds: 1));
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
        context.push(
          '/browser?url=${Uri.encodeComponent(url)}&intercept=false',
        );
      }
    case '__external__':
      await launchUrl(uri, mode: LaunchMode.externalApplication);
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
