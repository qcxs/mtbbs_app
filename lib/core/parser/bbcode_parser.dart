/// BBCode → AST 解析器
///
/// 职责链：Tokenizer → TreeBuilder → ParagraphGrouper
///
/// 节点类型：
///   块级容器: doc, quote, free, hide, align, list, listItem
///   块级原子: code, img, audio, media, attach, hr, table, tr, td
///   内联容器: bold, italic, underline, strikethrough,
///             color, size, font, backcolor, background, link, url, email, qq
///   内联原子: text, lineBreak
///
/// quote / free / hide 三者语义不同但 CSS 相同（黄底容器）：
///   quote → 引用
///   free  → 免费可见内容
///   hide  → 需回复/积分可见

part 'bbcode_parser_lexer.dart';
part 'bbcode_parser_nodes.dart';
part 'bbcode_parser_tree.dart';

class BBCodeParser {
  final Map<String, String>? _originalMap;
  final Map<String, String>? _smilieIdMap;
  Map<String, String>? _enhancedMap;

  BBCodeParser({
    Map<String, String>? emojiMap,
    Map<String, String>? smilieIdMap,
  }) : _originalMap = emojiMap,
       _smilieIdMap = smilieIdMap;

  /// 经过预处理的增强 emojiMap，包含 [emoji_N] → imageUrl 映射。
  /// 调用 [parse] 后生效。当前渲染链路已改走
  /// `BBCode2Html → flutter_widget_from_html`，本解析器仅保留给
  /// 三层渲染诊断（docs/07）取 AST 层输出使用。
  Map<String, String>? get enhancedMap => _enhancedMap;

  static final _selfClosing = <String>{
    'hr',
    'img',
    'audio',
    'media',
    'attach',
    'attachimg',
    'appdata',
  };

  // 需要捕获内容作为 value 的标签（[img]url[/img] 等）
  static final _captureContent = <String>{
    'img',
    'audio',
    'media',
    'attach',
    'attachimg',
    'appdata',
  };

  /// 解析 [img=W,H] 格式的宽高
  static void _parseImgDimensions(String raw, Map<String, String> attrs) {
    final parts = raw.split(',');
    if (parts.length == 2) {
      final w = int.tryParse(parts[0].trim());
      final h = int.tryParse(parts[1].trim());
      if (w != null && w > 0) attrs['imgWidth'] = w.toString();
      if (h != null && h > 0) attrs['imgHeight'] = h.toString();
    }
  }

  static final _knownTags = <String>{
    'b',
    'i',
    'u',
    's',
    'color',
    'size',
    'font',
    'backcolor',
    'background',
    'url',
    'email',
    'qq',
    'quote',
    'free',
    'hide',
    'code',
    'list',
    'align',
    '*',
    'table',
    'tr',
    'td',
    'hr',
    'img',
    'audio',
    'media',
    'attach',
    'attachimg',
    'appdata',
  };

  List<AstNode> parse(String input) {
    final processed = _preprocess(input);
    final tokens = _tokenize(processed);
    final raw = _buildTree(tokens);
    final grouped = _groupParagraphs(raw);
    return _cleanTree(grouped);
  }

  static const _inlineTypes = <String>{
    'text',
    'lineBreak',
    'bold',
    'italic',
    'underline',
    'strikethrough',
    'color',
    'size',
    'font',
    'backcolor',
    'background',
    'emoji',
    'img',
    'attachimg',
  };

  // 纯样式标签，不含内容时可安全移除
  static const _styleOnlyTags = <String>{
    'bold',
    'italic',
    'underline',
    'strikethrough',
    'color',
    'size',
    'font',
    'backcolor',
    'background',
    'link',
    'url',
    'email',
    'qq',
  };
}
