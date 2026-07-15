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

class AstNode {
  final String type;
  final Map<String, dynamic> attrs;
  final List<AstNode> children;
  final String? text;

  AstNode({
    required this.type,
    Map<String, dynamic>? attrs,
    List<AstNode>? children,
    this.text,
  }) : attrs = attrs ?? {},
       children = children ?? [];

  Map<String, dynamic> toJson() => {
    'type': type,
    if (attrs.isNotEmpty) 'attrs': Map.from(attrs),
    if (children.isNotEmpty)
      'children': children.map((c) => c.toJson()).toList(),
    if (text != null) 'text': text,
  };
}

enum TokenKind { text, newline, open, close, selfClosing }

class Token {
  final TokenKind kind;
  final String? tag;
  final String? text;
  final Map<String, String> attrs;

  Token._({required this.kind, this.tag, this.text, Map<String, String>? attrs})
    : attrs = attrs ?? {};

  factory Token.text(String t) => Token._(kind: TokenKind.text, text: t);
  factory Token.newline() => Token._(kind: TokenKind.newline);
  factory Token.open(String tag, [Map<String, String>? attrs]) =>
      Token._(kind: TokenKind.open, tag: tag, attrs: attrs);
  factory Token.close(String tag) => Token._(kind: TokenKind.close, tag: tag);
  factory Token.selfClosing(String tag, [Map<String, String>? attrs]) =>
      Token._(kind: TokenKind.selfClosing, tag: tag, attrs: attrs);
}

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
  /// 调用 [parse] 后生效，用于传给 PostAstWidget 正确渲染所有表情。
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

  /// 预处理器：URL 归一化 + 表情替换
  ///
  /// 1. [url]href[/url] → [url=href]href[/url]（统一格式）
  /// 2. 保护 [code] 块
  /// 3. 替换表情文本为 [emoji_{smilieId}]
  String _preprocess(String input) {
    // 先提取 [code] 块保护起来
    final codeBlocks = <String>[];
    String text = input.replaceAllMapped(
      RegExp(r'\[code\]([\s\S]*?)\[/code\]'),
      (m) {
        codeBlocks.add(m.group(0)!);
        return '\x00CODE${codeBlocks.length - 1}\x00';
      },
    );

    // 1. 表情替换
    final map = _originalMap;
    if (map != null && map.isNotEmpty) {
      final idByText = <String, String>{};
      if (_smilieIdMap != null) {
        for (final e in _smilieIdMap.entries) {
          idByText[e.value] = e.key;
        }
      }
      final entries = map.entries.toList()
        ..sort((a, b) => b.key.length.compareTo(a.key.length));
      _enhancedMap = Map<String, String>.from(map);
      for (final entry in entries) {
        final insertText = entry.key;
        final smilieId = idByText[insertText];
        if (smilieId == null) continue;
        final marker = '[emoji_$smilieId]';
        _enhancedMap![marker] = entry.value;
        text = text.replaceAll(insertText, marker);
      }
    }

    // 3. 恢复 [code] 块
    for (int j = 0; j < codeBlocks.length; j++) {
      text = text.replaceAll('\x00CODE${j}\x00', codeBlocks[j]);
    }

    return text;
  }

  // ==================== Tokenizer ====================

  List<Token> _tokenize(String input) {
    final tokens = <Token>[];
    final buf = StringBuffer();
    int i = 0;

    void flush() {
      if (buf.isNotEmpty) {
        tokens.add(Token.text(buf.toString()));
        buf.clear();
      }
    }

    while (i < input.length) {
      final ch = input[i];
      if (ch == '[') {
        final end = input.indexOf(']', i + 1);
        if (end == -1) {
          buf.write(ch);
          i++;
          continue;
        }
        final inner = input.substring(i + 1, end);
        flush();

        if (inner.startsWith('/')) {
          final tag = inner.substring(1).trim().toLowerCase();
          if (_knownTags.contains(tag)) {
            tokens.add(Token.close(tag));
          } else {
            buf.write(input.substring(i, end + 1));
          }
        } else if (inner.startsWith('*')) {
          tokens.add(Token.selfClosing('*'));
        } else {
          final eqIdx = inner.indexOf('=');
          String tag;
          String? rawValue;
          if (eqIdx == -1) {
            tag = inner.trim().toLowerCase();
          } else {
            tag = inner.substring(0, eqIdx).trim().toLowerCase();
            rawValue = inner.substring(eqIdx + 1);
          }
          if (_knownTags.contains(tag)) {
            // 处理 code 块：捕获到 [/code] 之间的全部原始文本
            if (tag == 'code') {
              final closeTag = '[/code]';
              final closeIdx = input.indexOf(closeTag, end + 1);
              if (closeIdx != -1) {
                final rawContent = input.substring(end + 1, closeIdx);
                tokens.add(Token.open('code'));
                tokens.add(Token.text(rawContent));
                tokens.add(Token.close('code'));
                i = closeIdx + closeTag.length;
                continue;
              }
            }

            // 处理 [img]/[audio]/[media]/[attach]：捕获内容作为 value
            if (_captureContent.contains(tag)) {
              final closeTag = '[/$tag]';
              final closeIdx = input.indexOf(closeTag, end + 1);
              if (closeIdx != -1) {
                final rawContent = input.substring(end + 1, closeIdx);
                final attrs = <String, String>{'value': rawContent};
                // 兼容 [img=W,H] 语法
                if (rawValue != null && tag == 'img') {
                  _parseImgDimensions(rawValue, attrs);
                }
                tokens.add(Token.selfClosing(tag, attrs));
                i = closeIdx + closeTag.length;
                continue;
              }
            }

            // [url]href[/url] → 捕获内容同时作为 value 和显示文本
            if (tag == 'url' && rawValue == null) {
              final closeTag = '[/url]';
              final closeIdx = input.indexOf(closeTag, end + 1);
              if (closeIdx != -1) {
                final rawContent = input.substring(end + 1, closeIdx);
                tokens.add(Token.open('url', {'value': rawContent}));
                tokens.add(Token.text(rawContent));
                tokens.add(Token.close('url'));
                i = closeIdx + closeTag.length;
                continue;
              }
            }

            final attrs = <String, String>{};
            if (rawValue != null) attrs['value'] = rawValue;
            if (_selfClosing.contains(tag)) {
              tokens.add(Token.selfClosing(tag, attrs));
            } else {
              tokens.add(Token.open(tag, attrs));
            }
          } else {
            // 未知标签 → 检查是否是表情
            final emojiKey = '[$inner]';
            final effectiveMap = _enhancedMap ?? const {};
            if (effectiveMap.containsKey(emojiKey)) {
              tokens.add(Token.selfClosing('emoji', {'value': '$inner'}));
            } else {
              buf.write(input.substring(i, end + 1));
            }
          }
        }
        i = end + 1;
      } else if (ch == '\n') {
        flush();
        tokens.add(Token.newline());
        i++;
      } else if (ch == '\r') {
        i++;
      } else {
        buf.write(ch);
        i++;
      }
    }
    flush();
    return tokens;
  }

  // ==================== Tree Builder ====================

  List<AstNode> _buildTree(List<Token> tokens) {
    final root = AstNode(type: 'doc');
    final stack = <AstNode>[root];

    void append(AstNode node) => stack.last.children.add(node);

    void push(AstNode node) {
      stack.last.children.add(node);
      stack.add(node);
    }

    void popTo(String tag) {
      for (int j = stack.length - 1; j >= 0; j--) {
        if (stack[j].type == tag) {
          stack.removeRange(j, stack.length);
          return;
        }
      }
    }

    for (final token in tokens) {
      switch (token.kind) {
        case TokenKind.text:
          append(AstNode(type: 'text', text: token.text));
        case TokenKind.newline:
          final last = stack.last.children.isNotEmpty
              ? stack.last.children.last
              : null;
          if (last?.type != 'lineBreak') append(AstNode(type: 'lineBreak'));
        case TokenKind.open:
          {
            // BBCode 标签名 → AST 节点类型名
            const nameMap = <String, String>{
              'b': 'bold',
              'i': 'italic',
              'u': 'underline',
              's': 'strikethrough',
              'url': 'link',
              'background': 'backcolor',
              'hr': 'thematicBreak',
            };
            final type = nameMap[token.tag!] ?? token.tag!;
            push(AstNode(type: type, attrs: Map.from(token.attrs)));
          }
        case TokenKind.close:
          {
            const nameMap = <String, String>{
              'b': 'bold',
              'i': 'italic',
              'u': 'underline',
              's': 'strikethrough',
              'url': 'link',
              'background': 'backcolor',
              'hr': 'thematicBreak',
            };
            popTo(nameMap[token.tag!] ?? token.tag!);
          }
        case TokenKind.selfClosing:
          if (token.tag == '*') {
            if (stack.last.type == 'listItem') stack.removeLast();
            push(AstNode(type: 'listItem'));
          } else {
            append(AstNode(type: token.tag!, attrs: Map.from(token.attrs)));
          }
      }
    }
    return root.children;
  }

  // ==================== Paragraph Grouper ====================

  List<AstNode> _groupParagraphs(List<AstNode> nodes) {
    final result = <AstNode>[];
    AstNode? para;

    void flush() {
      if (para != null && para!.children.isNotEmpty) {
        result.add(para!);
        para = null;
      }
    }

    for (final node in nodes) {
      if (_isInline(node)) {
        para ??= AstNode(type: 'paragraph');
        para!.children.add(node);
      } else {
        flush();
        if ((node.type == 'listItem' ||
                node.type == 'list' ||
                _isContainer(node)) &&
            node.children.isNotEmpty) {
          final copy = node.children.toList();
          node.children
            ..clear()
            ..addAll(_groupParagraphs(copy));
        }
        result.add(node);
      }
    }
    flush();
    return result;
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

  bool _isInline(AstNode n) => _inlineTypes.contains(n.type);
  bool _isContainer(AstNode n) =>
      n.type == 'doc' ||
      n.type == 'quote' ||
      n.type == 'free' ||
      n.type == 'hide' ||
      n.type == 'align' ||
      n.type == 'link' ||
      n.type == 'email' ||
      n.type == 'qq';

  // ==================== Tree Cleaner ====================

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

  /// 清理 AST 中的空节点：
  ///   1. 纯空白文本节点 → 移除
  ///   2. 无子节点的样式标签 → 移除（如 [size=4] [/size]）
  List<AstNode> _cleanTree(List<AstNode> nodes) {
    final result = <AstNode>[];
    for (final node in nodes) {
      // 递归清理子节点
      final cleaned = node.children.isEmpty
          ? node
          : AstNode(
              type: node.type,
              attrs: Map.from(node.attrs),
              text: node.text,
              children: _cleanTree(node.children),
            );

      // 纯空白文本节点 → 跳过
      if (cleaned.type == 'text' &&
          cleaned.text != null &&
          cleaned.text!.trim().isEmpty) {
        continue;
      }

      // 无子节点的样式标签 → 跳过
      if (_styleOnlyTags.contains(cleaned.type) && cleaned.children.isEmpty) {
        continue;
      }

      // 只包含空白/换行的空段落 → 跳过（减少不必要的行间距）
      if (cleaned.type == 'paragraph' &&
          cleaned.children.every(
            (c) =>
                c.type == 'lineBreak' ||
                (c.type == 'text' && c.text != null && c.text!.trim().isEmpty),
          )) {
        continue;
      }

      result.add(cleaned);
    }
    return result;
  }
}
