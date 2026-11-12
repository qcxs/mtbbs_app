import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:mtbbs/core/app/site_store.dart';
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
String htmlToMarkdown(dom.Element root) {
  final math = _MathCollector();
  final markdown = _Html2Markdown(math).convert(root);
  return math.restoreMarkdown(markdown);
}

/// Parsedown 容器 → 展示用内容
///
/// 52pojie 站点直接输出 `[md]…[/md]`（服务端原生支持），保留逆向还原出的
/// Markdown，由渲染层用 `package:markdown` 解析；公式 / 附件仍以
/// `[appdata]` 形式内嵌，渲染层会先保护它们再解析 Markdown。
///
/// 其它站点（或测试环境未初始化站点）回退到 BBCode：
/// `Parsedown HTML →（本模块）Markdown → markdownToBbcode → BBCode`。
String parsedownHtmlToBbcode(dom.Element root) {
  final math = _MathCollector();
  final attachments = _AttachmentCollector();
  final markdown = _Html2Markdown(math, attachments: attachments).convert(root);
  if (markdown.trim().isEmpty) return '';
  if (_siteSupportsMdTag()) {
    final md = attachments.restore(math.restoreBbcode(markdown)).trim();
    return '[md]$md[/md]';
  }
  final bbcode = markdownToBbcode(markdown, templates: _displayTemplates);
  return attachments.restore(math.restoreBbcode(bbcode));
}

/// 是否由服务端原生渲染 `[md]…[/md]`。
///
/// 目前只有 52pojie 的 Markdown 插件支持，其余站点发 `[md]` 只会当成纯文本。
bool _siteSupportsMdTag() {
  final store = SiteStore.instance;
  return store.sites.isNotEmpty && SiteStore.supportsMdTag(store.host);
}

/// 普通附件（`<ignore_js_op>` 内 `a[href*=mod=attachment]`）收集器
///
/// 与数学公式同理，JSON 不能直接写进 Markdown：文件名里的 `_`、`*`、`[]`
/// 会被 Markdown 转义/解释，往返后 JSON 就坏了。解析期间先用控制字符占位，
/// 转成 BBCode 后再替换为 `[appdata]`。
class _AttachmentCollector {
  final List<String> items = [];

  String add(Map<String, dynamic> data) {
    items.add(jsonEncode(data));
    return '\x00ATTACH${items.length - 1}\x00';
  }

  String restore(String text) => text.replaceAllMapped(
    RegExp(r'\x00ATTACH(\d+)\x00'),
    (m) => '[appdata]${items[int.parse(m.group(1)!)]}[/appdata]',
  );
}

/// 数学公式（`.math-render`）收集器
///
/// 解析期间先用占用符（`\x00MATH0\x00`）代替公式，转换结束后再还原。
/// **不能**在还原出的 Markdown 文本里直接写 `[appdata]{…}`：JSON 中的 LaTeX
/// 反斜杠（`\\frac`）会在 Markdown 的反斜杠转义阶段被吃掉，JSON 随之损坏。
class _MathCollector {
  final List<_MathItem> items = [];

  String add(String tex, {required bool display}) {
    items.add(_MathItem(tex, display));
    return '\x00MATH${items.length - 1}\x00';
  }

  /// Markdown 场景：还原成 `$…$` / `$$…$$`
  String restoreMarkdown(String text) => text.replaceAllMapped(
    RegExp(r'\x00MATH(\d+)\x00'),
    (m) {
      final item = items[int.parse(m.group(1)!)];
      final fence = item.display ? r'$$' : r'$';
      return '$fence${item.tex}$fence';
    },
  );

  /// BBCode 场景：还原成 App 私有展示载荷 `[appdata]`
  String restoreBbcode(String text) => text.replaceAllMapped(
    RegExp(r'\x00MATH(\d+)\x00'),
    (m) {
      final item = items[int.parse(m.group(1)!)];
      final json = jsonEncode({
        'type': 'math',
        'tex': item.tex,
        'display': item.display,
      });
      return '[appdata]$json[/appdata]';
    },
  );
}

class _MathItem {
  final String tex;
  final bool display;

  const _MathItem(this.tex, this.display);
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
  _Html2Markdown(this._math, {_AttachmentCollector? attachments})
    : _attachments = attachments;

  final _MathCollector _math;

  /// 非空时把普通附件转成 `[appdata]` 占位符（BBCode 阅读场景）；
  /// 为空时（纯 Markdown 输出）转成普通链接。
  final _AttachmentCollector? _attachments;

  String convert(dom.Element root) => _blocksOf(root).trim();

  /// `.math-render`：52pojie Markdown 插件的公式容器。
  /// 内容是 `$$…$$`（块级）或 `$…$`（行内）包裹的原始 LaTeX。
  static ({String tex, bool display})? _parseMath(dom.Element el) {
    final raw = el.text.replaceAll('\u00a0', ' ').trim();
    if (raw.length >= 4 && raw.startsWith(r'$$') && raw.endsWith(r'$$')) {
      return (tex: raw.substring(2, raw.length - 2).trim(), display: true);
    }
    if (raw.length >= 2 && raw.startsWith(r'$') && raw.endsWith(r'$')) {
      return (tex: raw.substring(1, raw.length - 1).trim(), display: false);
    }
    // 没有 `$` 分隔符（如 `\(…\)`）时按普通文本处理，交由既有逻辑转义
    return null;
  }

  // ==================== 块级 ====================

  /// Parsedown 容器里可能**混排**块级元素与容器级行内流
  /// （如 `文字 <code>x</code> 文字<br>` 直接挂在 `div.parsedown-markdown`
  /// 下，没有 `<p>` 包裹）。行内节点必须攒成一段再输出——逐个当块处理会把
  /// 一句话拆成多段、行内代码独占一行。
  String _blocksOf(dom.Element el) {
    final buf = StringBuffer();
    final inlineRun = StringBuffer();

    void flushInline() {
      final text = inlineRun.toString().trim();
      inlineRun.clear();
      if (text.isEmpty) return;
      buf.write('${_escapeBlockStart(text)}\n\n');
    }

    for (final node in el.nodes) {
      if (_isBlockNode(node)) {
        flushInline();
        buf.write(_block(node));
      } else {
        inlineRun.write(_inline(node));
      }
    }
    flushInline();
    return buf.toString();
  }

  /// 块级标签集合（与 [_block] 的 switch 对齐）
  static const _blockTags = <String>{
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'p',
    'pre',
    'blockquote',
    'ul',
    'ol',
    'table',
    'hr',
    'div',
    'ignore_js_op',
  };

  bool _isBlockNode(dom.Node node) =>
      node is dom.Element && _blockTags.contains(node.localName);

  String _block(dom.Node node) {
    if (node is! dom.Element) return '';
    // 块级公式：<div class="math-render">$$…$$</div>
    if (node.classes.contains('math-render')) {
      final math = _parseMath(node);
      if (math == null) return '';
      return '${_math.add(math.tex, display: math.display)}\n\n';
    }
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
        final attach = _attachment(node);
        if (attach != null) return '$attach\n\n';
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
    final contentIndent = '$indent    ';
    var index = 0;
    for (final li in el.children) {
      if (li.localName != 'li') continue;
      index++;
      // 列表项内可能混排行内流与块级内容（Parsedown 允许 `- 文字` 下缩进的
      // 代码块 / 表格）。块级节点必须按块输出并缩进挂在项下；若走 `_inline`，
      // 会被摊平成一行文字，代码块与表格结构全部丢失（docs/07 #124）。
      final parts = <String>[];
      final inlineRun = StringBuffer();

      void flushInline() {
        final text = inlineRun
            .toString()
            .replaceAll(RegExp(r'\s*\n\s*'), ' ')
            .trim();
        inlineRun.clear();
        if (text.isNotEmpty) parts.add(text);
      }

      for (final child in li.nodes) {
        if (child is dom.Element &&
            (child.localName == 'ul' || child.localName == 'ol')) {
          flushInline();
          // 用相对深度生成，缩进由下方 contentIndent 统一添加
          parts.add(
            _list(
              child,
              ordered: child.localName == 'ol',
              depth: 0,
            ).trim(),
          );
        } else if (_isBlockNode(child)) {
          flushInline();
          final block = _block(child).trim();
          if (block.isNotEmpty) parts.add(block);
        } else {
          inlineRun.write(_inline(child));
        }
      }
      flushInline();

      final lines = <String>[];
      for (var i = 0; i < parts.length; i++) {
        if (i > 0) lines.add('');
        lines.addAll(parts[i].split('\n'));
      }

      buf.write('$indent${ordered ? '$index.' : '-'}');
      if (lines.isNotEmpty) buf.write(' ${lines.first}');
      buf.writeln();
      for (final line in lines.skip(1)) {
        buf.writeln(line.trim().isEmpty ? '' : '$contentIndent$line');
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
    // 单元格内容已经是 Markdown 片段（`**粗体**`、`[文本](链接)` 等），
    // 不能再整体 _escapeText——那会把生成的语法转义成字面量（曾导致单元格里的
    // 加粗显示成 `**xxx**`、链接变成 `[url]([url=…]…[/url])`）。
    // 文本节点的转义已由 _inline 内部完成，这里只需处理 GFM 的列分隔符。
    String cellText(dom.Element cell) => _inlinesOf(cell)
        .replaceAll(RegExp(r'\s*\n\s*'), ' ')
        .trim()
        .replaceAll('|', r'\|');

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
    // 行内公式：<span class="math-render">$…$</span>
    if (node.classes.contains('math-render')) {
      final math = _parseMath(node);
      if (math == null) return _inlinesOf(node);
      return _math.add(math.tex, display: math.display);
    }
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
        final attach = _attachment(node);
        if (attach != null) return attach;
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

  /// `<ignore_js_op>` 内的普通附件（图片附件之外的 zip/rar 等）
  ///
  /// 结构：
  /// ```html
  /// <ignore_js_op>
  ///   <img src=".../filetype/zip.gif">
  ///   <span id="attach_N">
  ///     <a href="forum.php?mod=attachment&aid=...">name.zip</a>
  ///     <em class="xg1">(1.67 MB, 下载次数: 4329)</em>
  ///   </span>
  /// </ignore_js_op>
  /// ```
  /// 文件类型图标（zip.gif）没有展示价值，绝不能当普通图片输出——否则文件名、
  /// 大小、下载入口全部丢失，正文只剩一张图标（52pojie Markdown 帖 2117334）。
  ///
  /// BBCode 阅读场景转成 [appdata] 占位符（由 [_AttachmentCollector] 还原），
  /// 纯 Markdown 输出则转成普通链接。
  String? _attachment(dom.Element op) {
    final link = op.querySelector('a[href*="mod=attachment"]');
    if (link == null) return null;
    final href = (link.attributes['href'] ?? '').trim();
    if (href.isEmpty) return null;

    final name = link.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final emText = op.querySelector('em.xg1')?.text ?? '';
    final size =
        RegExp(r'\(([^,]+)').firstMatch(emText)?.group(1)?.trim() ?? '';
    final downloads =
        RegExp(r'下载次数[：:]\s*(\d+)').firstMatch(emText)?.group(1) ?? '';
    final aid = RegExp(r'aid=([^&]+)').firstMatch(href)?.group(1) ?? '';
    final url = normalizeUrl(href);

    final collector = _attachments;
    if (collector != null) {
      return collector.add({
        'type': 'attach',
        if (aid.isNotEmpty) 'aid': aid,
        'name': name.isEmpty ? '附件' : name,
        if (size.isNotEmpty) 'size': size,
        if (url.isNotEmpty) 'url': url,
        if (downloads.isNotEmpty) 'downloads': downloads,
      });
    }
    final text = name.isEmpty ? url : name;
    return '[$text](${_destination(url)})';
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
