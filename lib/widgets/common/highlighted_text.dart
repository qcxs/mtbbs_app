import 'package:flutter/material.dart';

/// 关键词高亮的纯文本组件
///
/// 在 [text] 中把 [keyword] 的所有（大小写不敏感的）出现处用 [highlightStyle]
/// 强调，其余部分沿用 [style]。未命中时退化为普通 `Text`（不产生多余 span）。
///
/// 用于搜索结果等"已知关键词"的场景；服务端返回的 `<strong><font>` 高亮标记
/// 在解析层已被剥成纯文本（见 docs/02 数据层边界），故这里按关键词自行匹配。
class HighlightedText extends StatelessWidget {
  final String text;
  final String keyword;
  final TextStyle? style;

  /// 命中片段样式（颜色/字重等，字号等基础样式仍从 [style] 继承）
  final TextStyle? highlightStyle;
  final int maxLines;
  final TextOverflow overflow;
  final TextAlign? textAlign;

  const HighlightedText(
    this.text, {
    super.key,
    required this.keyword,
    this.style,
    this.highlightStyle,
    this.maxLines = 2,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    final spans = buildHighlightSpans(
      text,
      keyword,
      highlight: highlightStyle,
    );
    if (spans == null) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
      );
    }
    return Text.rich(
      TextSpan(children: spans),
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
  }
}

/// 把 [text] 按 [keyword] 切成 TextSpan 列表；无关键词或未命中时返回 null。
///
/// 返回 null 表示"没有需要高亮的内容"，调用方可用普通 `Text` 渲染。
List<TextSpan>? buildHighlightSpans(
  String text,
  String keyword, {
  TextStyle? highlight,
}) {
  final kw = keyword.trim();
  if (text.isEmpty || kw.isEmpty) return null;

  final lowerText = text.toLowerCase();
  final lowerKw = kw.toLowerCase();

  final spans = <TextSpan>[];
  var start = 0;
  while (true) {
    final idx = lowerText.indexOf(lowerKw, start);
    if (idx < 0) break;
    if (idx > start) spans.add(TextSpan(text: text.substring(start, idx)));
    spans.add(
      TextSpan(text: text.substring(idx, idx + kw.length), style: highlight),
    );
    start = idx + kw.length;
  }
  if (spans.isEmpty) return null;
  if (start < text.length) spans.add(TextSpan(text: text.substring(start)));
  return spans;
}
