import 'dart:convert';

import 'package:mtbbs/core/utils/string_utils.dart';
import 'package:mtbbs/core/utils/url_util.dart';

part 'bbcode2html_appdata.dart';
part 'bbcode2html_convert.dart';
part 'bbcode2html_emoji.dart';
part 'bbcode2html_lists.dart';
part 'bbcode2html_tables.dart';

/// 「纯样式」BBCode 标签 id 全集。
///
/// 这是「设置 → 禁用样式标签」与 MCP 精简输出**共用的唯一来源**，改这里即两边同步。
///
/// 刻意**不含 `strikethrough`**：删除线带有语义（表示内容被否定/作废），
/// 不属于可以随意丢弃的纯样式。
/// `imgDimension` 是"忽略图片宽高"的开关，文本层没有同名标签，删除时自然无副作用。
const bbcodeStyleTagIds = <String>[
  'bold',
  'italic',
  'underline',
  'color',
  'size',
  'font',
  'backcolor',
  'align',
  'imgDimension',
];

/// 删除指定的 BBCode 样式标签标记（保留标签内文本）。
///
/// 例：禁用 `color` 时 `[color=red]文字[/color]` → `文字`。
/// 只删除 `[tag]`、`[tag=xxx]`、`[/tag]` 标记本身，不触碰内容，也不涉及嵌套。
/// 渲染层（[BBCode2Html]）与 MCP 精简输出共用此实现，避免两处逻辑漂移。
String stripDisabledBbcodeTags(String text, Set<String> tagIds) {
  // 设置项 id → BBCode 实际标签名
  const tagMapping = {
    'bold': 'b',
    'italic': 'i',
    'underline': 'u',
    'strikethrough': 's',
  };
  // 次标签：禁用主标签时连带删除的同义标签
  const secondaryMapping = {
    'backcolor': ['background'],
  };
  var result = text;
  for (final tag in tagIds) {
    result = _stripTagMarkers(result, tagMapping[tag] ?? tag);
    for (final sec in secondaryMapping[tag] ?? const <String>[]) {
      result = _stripTagMarkers(result, sec);
    }
  }
  return result;
}

/// 删除全部 `[tag]`、`[tag=xxx]`、`[/tag]` 标记
String _stripTagMarkers(String text, String tag) => text.replaceAllMapped(
  RegExp('\\[$tag(?:=[^\\]]*)?\\]|\\[/$tag\\]', caseSensitive: false),
  (_) => '',
);

/// BBCode → HTML 转换器
///
/// 将 BBCode 字符串转换为 HTML，由 flutter_widget_from_html 渲染为 Widget。
/// 参考 docs/BBCode2Html.js 的转换逻辑实现。
///
/// 转换策略：
/// 1. 先保护 [code] 块（替换为占位符；内部一律按纯文本，避免被误转换）
/// 2. 保护 [appdata] 块（JSON 不应被 HTML 转义）—— 必须晚于 [code]，
///    否则 [code] 内的 appdata 会变成还原不了的占位符
/// 3. 逐一遍历 BBCode 标签替换为对应 HTML
/// 4. 表情文本替换为 <img>，新行替换为 <br>
/// 5. 恢复 [code] / [appdata] 占位符，并按文档顺序落地正文图片
class BBCode2Html {
  final Map<String, String>? _emojiMap;
  final Map<String, String>? _smilieIdMap;
  final Set<String>? _disabledTags;
  final String? _baseUrl;
  final bool _autoDetectUrls;
  final bool _emitCodePlaceholder;

  /// [convert] 后填充的 [code] 块内容（索引对应 HTML 中的
  /// `data-code-index`）。渲染层按索引取出原始代码文本，
  /// 交给代码高亮组件（[BbcodeCodeBlock]）渲染。
  final List<String> codeBlocks = [];

  /// [convert] 后填充的正文图片 URL（按 HTML 文档顺序，索引对应
  /// `data-img-index`，不含表情）。一段 BBCode 即一帖/一楼，
  /// 渲染层据此把该帖/该楼的图片组成一个可左右滑动的画廊。
  ///
  /// 这里的每一项都是**可直接使用**的地址（已解码实体、已补全域名），
  /// 渲染层原样请求、不做任何修正（见 docs/02「数据层 ↔ 渲染层职责边界」）。
  final List<String> imageUrls = [];

  /// 正文图片的发射点暂存（见 [_emitContentImage] / [_resolveContentImages]）
  final List<({String url, String tag})> _imageSlots = [];

  BBCode2Html({
    Map<String, String>? emojiMap,
    Map<String, String>? smilieIdMap,
    Set<String>? disabledTags,
    String? baseUrl,
    bool autoDetectUrls = true,
    bool emitCodePlaceholder = false,
  }) : _emojiMap = emojiMap,
       _smilieIdMap = smilieIdMap,
       _disabledTags = disabledTags,
       _baseUrl = baseUrl,
       _autoDetectUrls = autoDetectUrls,
       _emitCodePlaceholder = emitCodePlaceholder;

  /// 归一化/校验颜色值。
  ///
  /// 网页中 `<font color="#ff00">` 按 HTML color 属性的 legacy 语义解析为
  /// `#ff0000`（红色），CSS 规范则把 4 位 hex `#RGBA` 解读为带 alpha，
  /// 两者语义不同。这里对齐**网页 legacy 语义**：
  /// - 4 位 `#RRGG` → `#RRGG00`（R2 + G2，B 补 0）
  /// - 3 位 `#RGB` → `#RRGGBB`（标准 CSS 翻倍）
  /// - 6/8 位 hex 校验通过后原样返回
  /// - 非法 hex（如 `#FFYYTT`）返回空串，调用点据此省略样式
  ///   （渲染器的 CSS 颜色解析对非法值行为不定，省略最安全）
  /// - rgb()/rgba()、命名色原样返回
  static final _hex3 = RegExp(r'^#[0-9a-fA-F]{3}$');
  static final _hex4 = RegExp(r'^#[0-9a-fA-F]{4}$');
  static final _hex6 = RegExp(r'^#[0-9a-fA-F]{6}$');
  static final _hex8 = RegExp(r'^#[0-9a-fA-F]{8}$');

  static String _normalizeColor(String v) {
    final s = v.trim();
    if (s.startsWith('#')) {
      if (_hex4.hasMatch(s)) {
        return '#${s.substring(1, 3)}${s.substring(3, 5)}00';
      }
      if (_hex3.hasMatch(s)) {
        final c = s.substring(1);
        return '#${c[0]}${c[0]}${c[1]}${c[1]}${c[2]}${c[2]}';
      }
      if (_hex6.hasMatch(s) || _hex8.hasMatch(s)) return s;
      return '';
    }
    return v;
  }

  /// 记录一张正文图片（发射点），返回占位符。
  ///
  /// [url] 必须是**可直接使用**的地址（已解码实体、已补全域名）——渲染层
  /// 会原样拿去请求，不再做任何修正。契约见 docs/02「数据层 ↔ 渲染层职责边界」。
  ///
  /// [tag] 是待落地的 `<img>`，由 [_resolveContentImages] 按占位符在 HTML 中
  /// 出现的先后顺序统一展开。之所以先占位、最后落地（而不是当场写 `<img>`）：
  /// - `[appdata]` 图片附件在步骤 0 就被渲染，早于 `[img]`，直接写入会让
  ///   [imageUrls] 的次序与文档顺序不符；占位符按出现位置展开天然正确
  /// - URL 与 HTML 出自同一处、只写一次，渲染层拿到的值与 [imageUrls]
  ///   不会因为属性转义（`&` → `&amp;`）而漂移
  String _emitContentImage(String url, String tag) {
    _imageSlots.add((url: url, tag: tag));
    return '\x00IMG${_imageSlots.length - 1}\x00';
  }

  /// 按文档顺序把 `\x00IMG*` 占位符落地为 `<img data-img-index="N">`，
  /// 并同步填充 [imageUrls]（索引与 `data-img-index` 一一对应）。
  ///
  /// 表情 `<img>` 不经过占位符，因此天然不在画廊内，无需再做字符串判别。
  String _resolveContentImages(String html) {
    return html.replaceAllMapped(RegExp(r'\x00IMG(\d+)\x00'), (m) {
      final slot = int.tryParse(m.group(1)!) ?? -1;
      if (slot < 0 || slot >= _imageSlots.length) return '';
      final image = _imageSlots[slot];
      imageUrls.add(image.url);
      return image.tag.replaceFirst(
        '<img',
        '<img data-img-index="${imageUrls.length - 1}"',
      );
    });
  }

  /// 将相对 URL 解析为绝对 URL（未注入 baseUrl 或空串时原样返回）
  String _resolveUrl(String url) {
    if (url.isEmpty) return url;
    final baseUrl = _baseUrl;
    if (baseUrl == null) return url;
    return normalizeUrl(url, base: baseUrl);
  }

  /// 自动识别纯文本中的 http(s) URL 并转为可点击链接
  ///
  /// 保护已有 <a> 和 <img> 标签，避免二次包裹。
  String _autoLinkUrls(String html) {
    // 保护已有 HTML 标签
    final tags = <String>[];
    html = html.replaceAllMapped(
      RegExp(r'<a[\s\S]*?</a>|<img[\s\S]*?/>', caseSensitive: false),
      (m) {
        tags.add(m.group(0)!);
        return '\x00TAG${tags.length - 1}\x00';
      },
    );

    // 替换剩余纯文本中的 http(s) URL
    // 要求 URL 以字母/数字/`/` 结尾，自然排除尾部标点
    html = html.replaceAllMapped(
      RegExp(
        r'https?://[a-zA-Z0-9][a-zA-Z0-9./_~:?#@!$&()*+,;=%\[\]-]*[a-zA-Z0-9/]',
        caseSensitive: false,
      ),
      (m) {
        final url = m.group(0)!;
        return '<a href="$url" target="_blank">$url</a>';
      },
    );

    // 恢复保护的标签
    for (int i = 0; i < tags.length; i++) {
      html = html.replaceFirst('\x00TAG$i\x00', tags[i]);
    }
    return html;
  }

  /// [code] 内容转 HTML（保留缩进和格式）
  String _codeToHtml(String code) {
    // code 内容：空格保留、换行转 <br>；HTML 标签须转义（codeBlocks 现为
    // 原始代码文本），由渲染器解码实体后显示，避免 < > 破坏结构
    code = htmlEscape(code);
    final lines = code
        .split('\n')
        .map((l) => '<li>${l.isEmpty ? '<br>' : l}<br></li>')
        .join('');
    return '<pre><code><ol>$lines</ol></code></pre>';
  }

  /// 移除被禁用的 BBCode 标签（保留标签内的内容）
  ///
  /// 实现见顶层 [stripDisabledBbcodeTags] —— 与 MCP 精简输出共用同一份逻辑。
  String _stripDisabledTags(String html) =>
      stripDisabledBbcodeTags(html, _disabledTags!);

  /// 替换带值标签 [tag=value]...[/tag]
  String _replaceTag(
    String html,
    String tag,
    String Function(String match, String value) openReplacer,
    String closeTag,
  ) {
    var result = html;
    // 开标签 [tag=value]
    result = result.replaceAllMapped(
      RegExp('\\[$tag=([^\\]]+)\\]', caseSensitive: false),
      (m) => openReplacer(m.group(0)!, m.group(1)!),
    );
    // 关标签 [/tag]
    result = result.replaceAllMapped(
      RegExp('\\[/$tag\\]', caseSensitive: false),
      (_) => closeTag,
    );
    return result;
  }
}
