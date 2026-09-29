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

part 'post_html_widget_parts.dart';

/// 可被全局/局部禁用的 BBCode 样式标签
///
/// 不含 `strikethrough`：删除线带语义（内容被否定/作废），
/// 不应在"禁用样式"时被一并丢弃。
const bbcodeStyleTags = <String>{
  'bold',
  'italic',
  'underline',
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
    // 本段 BBCode（= 一帖/一楼）的全部正文图片，供画廊左右滑动
    final imageUrls = converter.imageUrls;

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
              galleryUrls: imageUrls,
              galleryIndex:
                  int.tryParse(element.attributes['data-img-index'] ?? '') ??
                  -1,
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
