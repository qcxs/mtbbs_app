import 'package:markdown/markdown.dart' as md;

import 'package:mtbbs/models/md_convert_templates.dart';

/// Markdown → BBCode 转换器
///
/// 与 [Html2BBCode]（Discuz 服务器 HTML → BBCode）方向相反、互不依赖：
/// 本模块只服务「用户粘贴 Markdown」场景，产出可直接提交给 Discuz 的 BBCode。
///
/// 管线：
/// ```
/// Markdown 文本
///   →（可选）剔除 Emoji
///   → 剥离 Front Matter（--- ... ---）→ [free]
///   → md.Document(GFM AST)
///   → 递归套模板 → BBCode
///   → 收敛空白（cleanResult）
/// ```
///
/// 设计要点（对齐 mt-convert 的 MarkdownToBbcodeConverter，并修掉其两处薄弱点）：
/// - **不产生 HTML 标签**：Discuz 会把 `<br>` 当普通文字显示，换行一律用 `\n`
/// - **嵌套引用只输出一层**：App 的 `[quote]` 是非贪婪匹配、不支持嵌套
///   （见 `bbcode2html.dart`），因此引用深度 >1 时只摊平内容、不再包裹
/// - **任务列表按 AST 节点判断**：mt-convert 靠「原文行 ↔ 转换后行」逐行对齐，
///   一旦行数错位就整段错位；这里直接读 `li` 内的 checkbox 节点
/// - **`[code]` 内部空行受保护**：cleanResult 的「压空行」规则不进入代码块，
///   否则代码里的空行会被吃掉
String markdownToBbcode(
  String markdown, {
  MdConvertTemplates templates = MdConvertTemplates.defaults,
  bool autoNumbering = false,
  bool removeEmoji = false,
}) {
  var input = markdown.trim();
  if (input.isEmpty) return '';
  if (removeEmoji) input = removeMdEmoji(input);

  // Front Matter（文档开头的 --- 元数据块）→ [free]
  var frontMatter = '';
  final fm = RegExp(r'^---\s*\n([\s\S]*?)\n---\s*\n*').firstMatch(input);
  if (fm != null) {
    frontMatter = '[free]\n${fm.group(1)!.trim()}\n[/free]\n';
    input = input.substring(fm.end).trimLeft();
  }

  final document = md.Document(
    // GFM：围栏代码块 / 表格 / 删除线 / 自动链接 / 任务列表
    extensionSet: md.ExtensionSet.gitHubFlavored,
    // ==高亮== 不属于 GFM 扩展集，用自定义语法接入
    inlineSyntaxes: [_HighlightSyntax()],
    // 关闭 HTML 转义：Text 节点保留原始字符，可直接写入 BBCode
    // （BBCode 不是 HTML，`<` `&` 无需实体化）
    encodeHtml: false,
  );

  final body = _MdToBbcodeRenderer(
    templates,
    autoNumbering: autoNumbering,
  ).render(document.parse(input));

  return _cleanResult(frontMatter + body);
}

/// `==高亮==`（Obsidian / 部分方言）→ `<mark>` 节点。
///
/// 官方 GFM 扩展集不含该语法；用自定义 InlineSyntax 比「转换完再跑正则」更稳
/// —— 不会误伤行内代码里的 `==`（代码跨度内的文本不参与其它语法匹配）。
class _HighlightSyntax extends md.InlineSyntax {
  // 0x3D == '='，用于快速预判，避免每个字符都跑正则
  _HighlightSyntax() : super(r'==([^\n]+?)==', startCharacter: 0x3D);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('mark', match[1]!));
    return true;
  }
}

/// AST → BBCode 的递归渲染器（每次转换新建实例，无跨调用状态）
class _MdToBbcodeRenderer {
  _MdToBbcodeRenderer(this.t, {required this.autoNumbering});

  final MdConvertTemplates t;
  final bool autoNumbering;

  /// 标题自动编号计数器（h1/h2/h3 各一位，h3 及以上共用第 3 位）
  final List<int> _headingCounters = [0, 0, 0];

  /// 当前引用深度：>0 表示已在 `[quote]` 内，嵌套引用只摊平内容
  int _quoteDepth = 0;

  String render(List<md.Node> nodes) => nodes.map(_node).join();

  // ==================== 节点分发 ====================

  String _node(md.Node node) {
    if (node is md.Text) return node.text;
    if (node is md.Element) return _element(node);
    return node.textContent;
  }

  String _children(md.Element el) =>
      el.children?.map(_node).join() ?? '';

  String _fill(String template, Map<String, String> vars) =>
      renderMdTemplate(template, vars);

  String _element(md.Element el) {
    switch (el.tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        return _heading(el, int.parse(el.tag.substring(1)));
      case 'p':
        return '${_fill(t.paragraph, {'text': _children(el)})}\n';
      case 'strong':
        return _fill(t.strong, {'text': _children(el)});
      case 'em':
        return _fill(t.em, {'text': _children(el)});
      case 'del':
        return _fill(t.del, {'text': _children(el)});
      case 'mark':
        return _fill(t.highlight, {'text': _children(el)});
      case 'code':
        // 行内代码（块级代码由 pre 分支整体处理，不会走到这里）
        return _fill(t.codespan, {'text': el.textContent});
      case 'pre':
        return _codeBlock(el);
      case 'blockquote':
        return _blockquote(el);
      case 'hr':
        return '${_fill(t.hr, const {})}\n';
      case 'br':
        return '\n';
      case 'ul':
        return _list(el, ordered: false);
      case 'ol':
        return _list(el, ordered: true);
      case 'li':
        return _listItem(el);
      case 'table':
        return _table(el);
      case 'thead':
      case 'tbody':
        return _children(el);
      case 'tr':
        return _fill(t.tablerow, {'content': _children(el)});
      case 'th':
      case 'td':
        // Discuz 表格没有 [th]，表头单元格同样输出 [td]
        return _fill(t.tablecell, {'content': _children(el)});
      case 'a':
        return _link(el);
      case 'img':
        return _image(el);
      case 'input':
        // 任务列表 checkbox 已在 _listItem 内消费，其余 input 丢弃
        return '';
      default:
        // 未知元素（如裸 HTML）只保留内容文本
        return _children(el);
    }
  }

  // ==================== 块级 ====================

  String _heading(md.Element el, int level) {
    final clamped = level > 3 ? 3 : level;
    var text = _children(el);
    if (autoNumbering) text = '${_headingNumber(clamped)} $text';
    final template = switch (clamped) {
      1 => t.heading1,
      2 => t.heading2,
      _ => t.heading3,
    };
    return '${_fill(template, {
      'text': text,
      'level': '$level',
      'size': '${4 - clamped}',
    })}\n';
  }

  String _headingNumber(int level) {
    _headingCounters[level - 1]++;
    for (var i = level; i < _headingCounters.length; i++) {
      _headingCounters[i] = 0;
    }
    return _headingCounters.take(level).join('.');
  }

  String _codeBlock(md.Element pre) {
    // [code] 不接受语言参数（与 App 现有渲染一致），语言信息丢弃
    final code = _codeText(pre);
    final block = _fill(t.code, {'text': code, 'lang': ''});
    // 模板默认在 [/code] 前留一个换行（Discuz 惯例），此处收敛，避免代码块尾部多一空行
    final normalized = block.replaceFirst(RegExp(r'\s*\[/code\]\s*$'), '[/code]');
    return '$normalized\n';
  }

  /// 取 `<pre>` 内 `<code>` 的纯文本；无 `<code>` 子节点时退回 `<pre>` 文本
  String _codeText(md.Element pre) {
    for (final child in pre.children ?? const <md.Node>[]) {
      if (child is md.Element && child.tag == 'code') {
        return child.textContent.trim();
      }
    }
    return pre.textContent.trim();
  }

  String _blockquote(md.Element el) {
    // 嵌套引用：App 的 [quote] 不支持嵌套（非贪婪匹配），只摊平内容
    if (_quoteDepth > 0) return '${_children(el).trim()}\n';
    _quoteDepth++;
    final content = _children(el).trim();
    _quoteDepth--;
    return '${_fill(t.blockquote, {'text': content})}\n';
  }

  String _list(md.Element el, {required bool ordered}) {
    final body = StringBuffer();
    for (final child in el.children ?? const <md.Node>[]) {
      body.write(_node(child));
    }
    return '${_fill(t.list, {
      'tag': ordered ? 'list=1' : 'list',
      'body': body.toString(),
    })}\n';
  }

  /// 渲染单个 `<li>`：任务列表项把 checkbox 节点转成 `[✓]` / `[✗]`
  String _listItem(md.Element li) {
    final buf = StringBuffer();
    var leading = true;
    for (final child in li.children ?? const <md.Node>[]) {
      if (leading &&
          child is md.Element &&
          child.tag == 'input' &&
          child.attributes['type'] == 'checkbox') {
        buf.write(child.attributes.containsKey('checked') ? '[✓] ' : '[✗] ');
      } else {
        buf.write(_node(child));
      }
      leading = false;
    }
    return '${_fill(t.listitem, {'text': buf.toString().trim()})}\n';
  }

  String _table(md.Element el) {
    final header = StringBuffer();
    final body = StringBuffer();
    for (final child in el.children ?? const <md.Node>[]) {
      if (child is md.Element && child.tag == 'thead') {
        header.write(_node(child));
      } else {
        body.write(_node(child));
      }
    }
    return '${_fill(t.table, {
      'header': header.toString(),
      'body': body.toString(),
    })}\n';
  }

  // ==================== 行内 ====================

  String _link(md.Element el) {
    final href = el.attributes['href'] ?? '';
    final text = _children(el).trim();
    if (href.isEmpty) return text;

    if (href.toLowerCase().startsWith('mailto:')) {
      final email = href.substring('mailto:'.length);
      final display = text.replaceFirst(RegExp(r'^mailto:', caseSensitive: false), '');
      if (display.isEmpty || display == email) return '[email]$email[/email]';
      return '[email=$email]$display[/email]';
    }

    return _fill(t.link, {
      'text': text.isEmpty ? href : text,
      'href': href,
      'title': el.attributes['title'] ?? '',
    });
  }

  String _image(md.Element el) {
    final href = el.attributes['src'] ?? '';
    if (href.isEmpty) return '';
    return _fill(t.image, {
      'href': href,
      'text': el.attributes['alt'] ?? '',
    });
  }
}

/// 收敛转换结果的空白。
///
/// 纯文本块之间的大量空行对 Discuz 没有意义，只会变成多余 `<br>`；
/// 但 `[code]` 内部的空行属于代码语义，必须先保护、最后还原。
String _cleanResult(String text) {
  final codes = <String>[];
  var out = text.replaceAllMapped(RegExp(r'\[code\][\s\S]*?\[/code\]'), (m) {
    codes.add(m.group(0)!);
    return '\x00CODE${codes.length - 1}\x00';
  });

  // 连续空行压成单换行
  out = out.replaceAll(RegExp(r'\n{2,}'), '\n');
  // 去掉开标签后的换行：`[b]\n文字` → `[b]文字`
  out = out.replaceAllMapped(
    RegExp(r'\[([a-z]+)\]\n+', caseSensitive: false),
    (m) => '[${m[1]}]',
  );
  // 去掉闭标签前的换行：`文字\n[/b]` → `文字[/b]`
  out = out.replaceAllMapped(
    RegExp(r'\n+\[/([a-z]+)\]', caseSensitive: false),
    (m) => '[/${m[1]}]',
  );

  for (var i = 0; i < codes.length; i++) {
    out = out.replaceFirst('\x00CODE$i\x00', codes[i]);
  }
  return out.trim();
}
