part of 'bbcode_parser.dart';

/// [BBCodeParser] 的预处理器与 Tokenizer。
///
/// 依赖的 static 集合/方法保留在宿主 [BBCodeParser] 中，此处以类名限定访问。
extension on BBCodeParser {
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
          if (BBCodeParser._knownTags.contains(tag)) {
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
          if (BBCodeParser._knownTags.contains(tag)) {
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
            if (BBCodeParser._captureContent.contains(tag)) {
              final closeTag = '[/$tag]';
              final closeIdx = input.indexOf(closeTag, end + 1);
              if (closeIdx != -1) {
                final rawContent = input.substring(end + 1, closeIdx);
                final attrs = <String, String>{'value': rawContent};
                // 兼容 [img=W,H] 语法
                if (rawValue != null && tag == 'img') {
                  BBCodeParser._parseImgDimensions(rawValue, attrs);
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
            if (BBCodeParser._selfClosing.contains(tag)) {
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
}
