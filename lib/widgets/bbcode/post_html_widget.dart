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

/// 段落间距 = 正文字号 × 该倍数。
///
/// 硬换行 `<br>` 在 flutter_widget_from_html 里只是文本里的 `'\n'`（不是盒子），
/// CSS 无法给“换行”本身加高。这里在 [customWidgetBuilder] 把 `<br>` 换成**块级
/// 间隔**（= 换行 + 段间距）。段内自动折行不含 `<br>`，因此仍只是 line-height，
/// 于是“段距 > 行距”，读起来不再串行。调整段间距只需改这个倍数。
const double _kParagraphGapRatio = 0.5;

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

  /// 是否自带 [SelectionArea]（文本选择作用域）。
  ///
  /// **编辑器预览必须传 false**：预览是"逐锚点"渲染的一列 `PostHtmlWidget`，
  /// 每个都自带 `SelectionArea` 的话，选区就被切成一格一格 —— 跨段选中直接
  /// 失效（嵌套 `SelectionArea` = 嵌套选区作用域）。预览改为在整列外面套
  /// **一个** `SelectionArea`，选区自然贯通全文。
  ///
  /// 正常帖子渲染保持默认 true，行为不变。
  final bool selectable;

  const PostHtmlWidget({
    super.key,
    required this.bbcode,
    this.fontSize,
    this.disabledTags,
    this.autoDetectUrls = true,
    this.selectable = true,
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
    // 代码块折叠行数（0 = 不限制）
    final codeBlockMaxLines = context.select<SettingsProvider, int>(
      (s) => s.codeBlockMaxLines,
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

    final htmlWidget = HtmlWidget(
      html,
      // flutter_widget_from_html 按 html 字符串缓存 widget 树，html 不变就
      // 不重建、也不会重跑 customWidgetBuilder。而 [code] 原文是走
      // `codeBlocks` 旁路注入的（HTML 里只有占位 div），代码变化时 html
      // 完全相同 → 缓存命中 → 代码块沿用旧内容；同理，只影响注入参数
      // （字号/图片宽度/代码块行数）的设置变更也不会生效。
      // 用「html + 注入参数 + 代码原文」的指纹作 key，任一变化即整体重建。
      key: ValueKey(
        Object.hashAll([
          html,
          textSize,
          maxImageWidth,
          codeBlockMaxLines,
          ...codeBlocks,
        ]),
      ),
      // 关闭异步构建：帖子正文需要与滚动同步构建，且便于测试确定性
      buildAsync: false,
      // height 即 CSS line-height（渲染器按 line-height 语义处理）。
      // 解析层会清掉空行使 BBCode 紧凑，段与段之间只剩单个 \n → 单个 <br>，
      // 段落间距因此等于行间距；而 <br> 是文本里的换行符、非盒子，CSS 无法单独
      // 撑开它。故统一放宽行高来缓解"串行"。中文正文 1.6 较舒适。
      textStyle: TextStyle(
        fontSize: textSize,
        color: cs.onSurface,
        height: 1.6,
      ),
      customStylesBuilder: (element) => _stylesFor(element, cs),
      customWidgetBuilder: (element) {
        // 硬换行 → 块级间隔：既完成换行，又提供段间距（见 _kParagraphGapRatio）。
        // 段内自动折行不经过这里，故只有“段落”被撑开。
        if (element.localName == 'br') {
          return SizedBox(height: textSize * _kParagraphGapRatio);
        }
        // [code] 占位 div → 代码高亮组件（块级）
        final codeIndex = element.attributes['data-code-index'];
        if (codeIndex != null) {
          final i = int.tryParse(codeIndex) ?? -1;
          if (i < 0 || i >= codeBlocks.length) return const SizedBox.shrink();
          return BbcodeCodeBlock(
            code: codeBlocks[i],
            // 代码块跟随正文字号，上限同步设置项上限（曾封顶 16，字号调大后代码块不跟）
            fontSize: textSize.clamp(11, 32).toDouble(),
            maxLines: codeBlockMaxLines,
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
          // data-img-index 是这张图在正文图片里的文档序（与 imageUrls 同下标）
          final imgIndex =
              int.tryParse(element.attributes['data-img-index'] ?? '') ?? -1;
          return BbcodeImage(
            url: src,
            explicitWidth: double.tryParse(element.attributes['width'] ?? ''),
            maxImageWidth: maxImageWidth.toDouble(),
            galleryUrls: imageUrls,
            galleryIndex: imgIndex,
          );
        }
        return null;
      },
      onTapUrl: (url) {
        _handleLinkTap(context, url);
        return true;
      },
    );
    // 选区作用域见 [selectable] 的说明
    return selectable ? SelectionArea(child: htmlWidget) : htmlWidget;
  }
}
