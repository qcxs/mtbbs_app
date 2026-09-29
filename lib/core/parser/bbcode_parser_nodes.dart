part of 'bbcode_parser.dart';

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
