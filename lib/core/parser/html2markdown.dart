import 'package:html/dom.dart' as dom;
import 'package:mtbbs/core/parser/md2bbcode.dart';
import 'package:mtbbs/core/utils/url_util.dart';
import 'package:mtbbs/models/md_convert_templates.dart';

/// Parsedown HTML → Markdown 文本（逆向还原）
///
/// 52pojie 的 Markdown 插件在**服务端**用 Parsedown 把 `[md]…[/md]` 渲染成
/// HTML，页面里没有原始 Markdown。这里把 Parsedown 产物还原成 Markdown，
/// 再交给既有 [markdownToBbcode] 走上渲染管线：
///
/// ```
/// Parsedown HTML →（本模块）Markdown → markdownToBbcode → BBCode → 渲染
/// ```
///
/// 只在 `div.parsedown-markdown` 容器内使用（由 [Html2BBCode] 判定），
/// 其它站点的 HTML 不走这里，因此不会影响既有解析结果。
String htmlToMarkdown(dom.Element root) => _Html2Markdown().convert(root);

/// Parsedown 容器 → 展示用 BBCode（[Html2BBCode] 直接拼接）
String parsedownHtmlToBbcode(dom.Element root) {
  final markdown = htmlToMarkdown(root);
  if (markdown.trim().isEmpty) return '';
  return markdownToBbcode(markdown, templates: _displayTemplates);
}

/// 展示用模板：只在「帖子阅读」场景使用。
///
/// [MdConvertTemplates.defaults] 的标题号（`4 - level` → 3/2/1）是为
/// **发帖回写 Discuz** 设计的；在本 App 的 `[size]` 映射（1→10px … 3→14px）下，
/// 标题会比正文还小。阅读场景按层级放大：h1=32px、h2=24px、h3=18px。
const _displayTemplates = MdConvertTemplates(
  heading1: '[size=6][b]\${text}[/b][/size]',
  heading2: '[size=5][b]\${text}[/b][/size]',
  heading3: '[size=4][b]\${text}[/b][/size]',
  paragraph: '\${text}',
  strong: '[b]\${text}[/b]',
  em: '[i]\${text}[/i]',
  del: '[s]\${text}[/s]',
  highlight: '[color=#000000][backcolor=#FFFF00]\${text}[/backcolor][/color]',
  codespan: '[color=#333333][backcolor=#f4f4f4]\${text}[/backcolor][/color]',
  code: '[code]\${text}\n[/code]',
  blockquote: '[quote]\${text}[/quote]',
  hr: '[hr]',
  link: '[url=\${href}]\${text}[/url]',
  image: '[img]\${href}[/img]',
  list: '[\${tag}]\n\${body}[/list]',
  listitem: '[*]\${text}',
  table: '[table]\${header}\${body}[/table]',
  tablerow: '[tr]\${content}[/tr]',
  tablecell: '[td]\${content}[/td]',
);

/// Parsedown DOM → Markdown 的递归转换器
///
/// 只覆盖 Parsedown 会产出的标签；未知标签保留其文本内容。
class _Html2Markdown {
  String convert(dom.Element root) => _blocksOf(root).trim();

  // ==================== 块级 ====================

  String _blocksOf(dom.Element el) => el.nodes.map(_block).join();

  String _block(dom.Node node) {
    if (node.nodeType == dom.Node.TEXT_NODE) {
      final text = (node.text ?? '').trim();
      return text.isEmpty ? '' : '${_escapeText(text)}\n\n';
    }
    if (node is! dom.Element) return '';
    final tag = node.localName ?? '';
    switch (tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        final level = int.parse(tag.substring(1));
        final text = _inlinesOf(node).trim();
        return text.isEmpty ? '' : '${'#' * level} $text\n\n';
      case 'p':
        final text = _escapeBlockStart(_inlinesOf(node).trim());
        return text.isEmpty ? '' : '$text\n\n';
      case 'pre':
        return _codeBlock(node);
      case 'blockquote':
        return _blockquote(node);
      case 'ul':
        return '${_list(node, ordered: false, depth: 0)}\n';
      case 'ol':
        return '${_list(node, ordered: true, depth: 0)}\n';
      case 'table':
        return '${_table(node)}\n';
      case 'hr':
        // 故意用 *** 而不是 ---：markdownToBbcode 会把开头的 `---…---`
        // 识别成 Front Matter 并转成 [free]
        return '***\n\n';
      case 'ignore_js_op':
        final img = node.querySelector('img');
        return img == null ? '' : '${_image(img)}\n\n';
      case 'div':
        // 附件信息浮层（.aimg_tip）等纯装饰容器直接跳过
        if (node.classes.contains('tip')) return '';
        return _blocksOf(node);
      default:
        final text = _inline(node).trim();
        return text.isEmpty ? '' : '$text\n\n';
    }
  }

  /// Code block：<pre> 内的 `<em>` 是「复制代码/隐藏代码」按钮，跳过；
  /// 代码文本一律取 `code.text`（hljs 的 `<span>` 会被扁平化为纯文本）。
  String _codeBlock(dom.Element pre) {
    final code = pre.querySelector('code');
    final raw = (code ?? pre).text;
    final text = _trimBlankLines(raw.replaceAll('\u00a0', ' '));
    if (text.isEmpty) return '';
    final lang = _languageOf(code);
    return '```$lang\n$text\n```\n\n';
  }

  String _blockquote(dom.Element el) {
    final inner = _blocksOf(el).trim();
    if (inner.isEmpty) return '';
    // 逐行加 `> ` 前缀，嵌套引用会自然累积成 `> > `
    final quoted = inner
        .split('\n')
        .map((line) => line.isEmpty ? '>' : '> $line')
        .join('\n');
    return '$quoted\n\n';
  }

  String _list(dom.Element el, {required bool ordered, required int depth}) {
    final buf = StringBuffer();
    final indent = '    ' * depth; // 4 空格对无序/有序 marker 都安全
    var index = 0;
    for (final li in el.children) {
      if (li.localName != 'li') continue;
      index++;
      final text = StringBuffer();
      final nested = <dom.Element>[];
      for (final child in li.nodes) {
        if (child is dom.Element &&
            (child.localName == 'ul' || child.localName == 'ol')) {
          nested.add(child);
        } else {
          text.write(_inline(child));
        }
      }
      final body = text.toString().replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();
      buf.writeln('$indent${ordered ? '$index.' : '-'} $body');
      for (final child in nested) {
        buf.write(
          _list(
            child,
            ordered: child.localName == 'ol',
            depth: depth + 1,
          ),
        );
      }
    }
    return buf.toString();
  }

  String _table(dom.Element el) {
    final rows = el.querySelectorAll('tr');
    if (rows.isEmpty) return '';
    List<dom.Element> cellsOf(dom.Element row) => row.children
        .where((c) => c.localName == 'th' || c.localName == 'td')
        .toList();
    String cellText(dom.Element cell) => _escapeText(
      _inlinesOf(cell).replaceAll(RegExp(r'\s*\n\s*'), ' ').trim(),
    ).replaceAll('|', r'\|');

    final header = cellsOf(rows.first);
    final buf = StringBuffer();
    buf.writeln('| ${header.map(cellText).join(' | ')} |');
    buf.writeln('| ${header.map((_) => '---').join(' | ')} |');
    for (final row in rows.skip(1)) {
      buf.writeln('| ${cellsOf(row).map(cellText).join(' | ')} |');
    }
    return buf.toString();
  }

  // ==================== 行内 ====================

  String _inlinesOf(dom.Element el) => el.nodes.map(_inline).join();

  String _inline(dom.Node node) {
    if (node.nodeType == dom.Node.TEXT_NODE) {
      return _escapeText(node.text ?? '');
    }
    if (node is! dom.Element) return '';
    final tag = node.localName ?? '';
    switch (tag) {
      case 'br':
        return '  \n';
      case 'strong':
      case 'b':
        return '**${_inlinesOf(node)}**';
      case 'em':
      case 'i':
        // <em class="CopyMyCode"> / <em class="hideCode"> 是插件按钮
        if (node.classes.contains('CopyMyCode') ||
            node.classes.contains('hideCode')) {
          return '';
        }
        return '*${_inlinesOf(node)}*';
      case 'del':
      case 'strike':
        return '~~${_inlinesOf(node)}~~';
      case 'code':
        return _inlineCode(node);
      case 'a':
        final href = (node.attributes['href'] ?? '').trim();
        final text = _inlinesOf(node).trim();
        if (href.isEmpty || href.startsWith('javascript:')) return text;
        return text.isEmpty ? '<$href>' : '[$text](${_destination(href)})';
      case 'img':
        return _image(node);
      case 'ignore_js_op':
        final img = node.querySelector('img');
        return img == null ? '' : _image(img);
      case 'div':
        if (node.classes.contains('tip')) return '';
        return _inlinesOf(node);
      default:
        return _inlinesOf(node);
    }
  }

  String _inlineCode(dom.Element el) {
    final text = el.text.replaceAll('\u00a0', ' ').trim();
    if (text.isEmpty) return '';
    // 内容含反引号时用双反引号包裹
    final fence = text.contains('`') ? '``' : '`';
    return '$fence$text$fence';
  }

  String _image(dom.Element img) {
    final raw =
        (img.attributes['file'] ??
                img.attributes['zoomfile'] ??
                img.attributes['src'] ??
                '')
            .trim();
    if (raw.isEmpty || isPlaceholderImageUrl(raw)) return '';
    final url = normalizeUrl(raw);
    if (url.isEmpty) return '';
    final alt = (img.attributes['alt'] ?? '').trim().replaceAll(
      RegExp(r'[\[\]\n]'),
      ' ',
    );
    return '![$alt](${_destination(url)})';
  }

  /// Markdown 链接目标：含空格或括号时用 `<...>` 包裹
  String _destination(String url) {
    if (url.contains(RegExp(r'[\s()]'))) return '<$url>';
    return url;
  }

  /// 取 `<code class="hljs language-xxx">` 的语言（`hljs` 本身跳过）
  String _languageOf(dom.Element? code) {
    if (code == null) return '';
    for (final cls in code.classes) {
      if (!cls.startsWith('language-')) continue;
      final lang = cls.substring('language-'.length);
      if (RegExp(r'^[A-Za-z0-9_+#.-]+$').hasMatch(lang)) return lang;
    }
    return '';
  }

  // ==================== 文本转义 ====================

  /// 转义会被 Markdown 解释成语法/HTML 的字符。
  ///
  /// Parsedown 输出的文本节点是**已经渲染过的正文**，若原样交给 Markdown
  /// 解析器，`*`、`_`、`[]`、`<>` 会被重新解释成语义，导致正文变形。
  /// 这些反斜杠在 `markdownToBbcode` 解析后即被还原，不会出现在 BBCode 里。
  String _escapeText(String text) => text
      .replaceAll(r'\', r'\\')
      .replaceAll('`', r'\`')
      .replaceAll('*', r'\*')
      .replaceAll('_', r'\_')
      .replaceAll('[', r'\[')
      .replaceAll(']', r'\]')
      .replaceAll('<', r'\<')
      .replaceAll('>', r'\>');

  /// 行首的块级语法（`#`、`-`、`+`、`1.`）需要转义，否则一行普通文字会变成
  /// 标题/列表。
  String _escapeBlockStart(String text) {
    final m = RegExp(r'^([#\-+]|\d+\.)\s').firstMatch(text);
    if (m == null) return text;
    return text.replaceRange(m.start, m.end, '\\${m.group(0)}');
  }

  String _trimBlankLines(String text) =>
      text.replaceAll(RegExp(r'^[\r\n]+'), '').replaceAll(RegExp(r'[\r\n]+$'), '');
}
