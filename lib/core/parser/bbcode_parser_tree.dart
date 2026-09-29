part of 'bbcode_parser.dart';

/// [BBCodeParser] 的 TreeBuilder / ParagraphGrouper / TreeCleaner。
///
/// 依赖的 static 集合（`_inlineTypes` / `_styleOnlyTags`）保留在宿主
/// [BBCodeParser] 中，此处以类名限定访问。
extension on BBCodeParser {
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

  bool _isInline(AstNode n) => BBCodeParser._inlineTypes.contains(n.type);
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
      if (BBCodeParser._styleOnlyTags.contains(cleaned.type) &&
          cleaned.children.isEmpty) {
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
