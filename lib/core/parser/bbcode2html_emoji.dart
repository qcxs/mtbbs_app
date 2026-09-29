part of 'bbcode2html.dart';

extension on BBCode2Html {
  /// 替换表情文本为 <img>
  String _replaceEmoji(String html) {
    final map = _emojiMap;
    if (map == null || map.isEmpty) return html;

    // 构建解析映射：insertText → imageUrl
    final resolved = <String, String>{};

    // 1. 直接从 _emojiMap 获取（insertText → imageUrl）
    for (final entry in map.entries) {
      resolved[entry.key] = entry.value;
    }

    // 2. 通过 _smilieIdMap 补充 [emoji_N] 格式映射
    if (_smilieIdMap != null && _smilieIdMap.isNotEmpty) {
      for (final entry in _smilieIdMap.entries) {
        final smilieId = entry.key;
        final insertText = entry.value;
        final imageUrl = map[insertText];
        if (imageUrl != null) {
          resolved['[emoji_$smilieId]'] = imageUrl;
        }
      }
    }

    // 3. 按长度降序替换（避免短匹配先行）
    final sortedEntries = resolved.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));

    for (final entry in sortedEntries) {
      final escapedKey = RegExp.escape(entry.key);
      html = html.replaceAllMapped(
        RegExp(escapedKey),
        (_) =>
            '<img src="${entry.value}" data-type="emoji" style="height:20px;vertical-align:middle;" />',
      );
    }

    return html;
  }
}
