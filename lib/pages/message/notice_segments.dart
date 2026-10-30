import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/core/utils/url_router.dart';
import 'package:mtbbs/core/utils/url_util.dart';

/// 渲染提醒 / 我的帖子的结构化段落（文本、用户、主题链接、换行、留言引用）。
///
/// [includeQuote] 为 true 时支持 `quote` 段（坛友互动等提醒才有留言引用）。
Widget buildNoticeSegments(
  BuildContext context,
  List<dynamic> segments, {
  bool includeQuote = false,
}) {
  final cs = Theme.of(context).colorScheme;
  final spans = <InlineSpan>[];
  final style = TextStyle(fontSize: 13, color: cs.onSurface, height: 1.4);
  final quoteStyle = TextStyle(
    fontSize: 12,
    color: cs.onSurfaceVariant,
    height: 1.4,
    fontStyle: FontStyle.italic,
  );
  final linkStyle = TextStyle(
    fontSize: 13,
    color: cs.onSurfaceVariant,
    decoration: TextDecoration.underline,
    height: 1.4,
  );

  for (final seg in segments) {
    final map = seg as Map<String, dynamic>;
    final type = map['type'] as String;
    // 换行段没有文本，须在下面的 text.isEmpty 跳过之前处理
    if (type == 'br') {
      spans.add(const TextSpan(text: '\n'));
      continue;
    }
    final text = map['text'] as String? ?? '';
    if (text.isEmpty) continue;

    switch (type) {
      case 'quote' when includeQuote:
        spans.add(TextSpan(text: '\n留言：', style: quoteStyle));
        spans.add(TextSpan(text: text, style: quoteStyle));
      case 'user':
        final uid = map['uid'] as String? ?? '';
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: GestureDetector(
              onTap: uid.isNotEmpty ? () => context.push('/user/$uid') : null,
              child: Text(text, style: linkStyle),
            ),
          ),
        );
      case 'thread':
        final url = map['url'] as String? ?? '';
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: GestureDetector(
              onTap: url.isNotEmpty
                  ? () {
                      // 链接落地的唯一决策点（App 内优先，兜底内置浏览器）
                      final target = UrlRouter.resolveTarget(normalizeUrl(url));
                      if (target != null) context.push(target);
                    }
                  : null,
              child: Text(text, style: linkStyle),
            ),
          ),
        );
      default:
        spans.add(TextSpan(text: text, style: style));
    }
  }
  return RichText(text: TextSpan(children: spans));
}
