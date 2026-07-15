import 'package:mtbbs/config/site_config.dart';

/// 解析 common_smilies_var.js → 结构化表情数据
///
/// JS 格式（Discuz 缓存生成，两个站点一致）：
/// ```
/// smilies_type['_{groupId}'] = ['组名', '文件夹名'];
/// smilies_array[{groupId}][{page}] = [
///   ['{smilieId}', '{insertText}', '{filename}', '{w}', '{h}', '{sort}'],
///   ...
/// ];
/// ```
///
/// 返回数据结构：
/// ```json
/// {
///   "success": true,
///   "groups": [
///     {
///       "id": 12,
///       "name": "默认",
///       "folder": "qq",
///       "emojis": [
///         {"smilieId": "1240", "insertText": "[呵呵]", "imageUrl": "..."},
///         ...
///       ]
///     }
///   ],
///   "smilieIdMap": {"1240": "[呵呵]", ...},
///   "insertTextMap": {"[呵呵]": "https://...", ...}
/// }
/// ```
Map<String, dynamic> parseResponse(String body, {String? baseUrl}) {
  if (body.isEmpty) {
    return {'success': false, 'message': 'empty response'};
  }

  // baseUrl 未传入时从 SiteConfig 获取（Flutter 环境）
  final imgBase = baseUrl ?? SiteConfig.baseUrl;

  // 1. 解析分组信息 smilies_type['_N'] = ['name', 'folder'];
  final typeRegex = RegExp(
    r"smilies_type\['_(\d+)'\] = \['([^']*)', '([^']*)'\]",
  );
  final groupInfos = <int, _GroupInfo>{};
  for (final m in typeRegex.allMatches(body)) {
    final id = int.parse(m.group(1)!);
    groupInfos[id] = _GroupInfo(id: id, name: m.group(2)!, folder: m.group(3)!);
  }

  // 2. 解析表情数组 smilies_array[N][P] = [[...], ...];
  final arrayHeaderRegex = RegExp(r"smilies_array\[(\d+)\]\[(\d+)\] = ");
  final headerMatches = arrayHeaderRegex.allMatches(body).toList();

  final groupEmojis = <int, List<_EmojiRaw>>{};

  for (final m in headerMatches) {
    final groupId = int.parse(m.group(1)!);
    final bodyStart = m.end;

    // 找到匹配的闭合 ]
    final end = _findMatchingBracket(body, bodyStart);
    if (end == null) continue;

    final arrayContent = body.substring(bodyStart, end + 1);
    final entries = _splitInnerArrays(arrayContent);

    for (final entry in entries) {
      final fields = _parseQuotedList(entry);
      if (fields.length >= 6) {
        groupEmojis
            .putIfAbsent(groupId, () => [])
            .add(
              _EmojiRaw(
                smilieId: fields[0],
                insertText: fields[1],
                filename: fields[2],
              ),
            );
      }
    }
  }

  // 3. 构建设返回数据
  final groups = <Map<String, dynamic>>[];
  final smilieIdMap = <String, String>{};
  final insertTextMap = <String, String>{};

  for (final entry in groupInfos.entries) {
    final gid = entry.key;
    final info = entry.value;
    final raws = groupEmojis[gid] ?? [];

    final emojis = raws.map((e) {
      final imageUrl = '$imgBase/static/image/smiley/${info.folder}/${e.filename}';
      smilieIdMap[e.smilieId] = e.insertText;
      insertTextMap[e.insertText] = imageUrl;
      return <String, String>{
        'smilieId': e.smilieId,
        'insertText': e.insertText,
        'imageUrl': imageUrl,
      };
    }).toList();

    groups.add({
      'id': gid,
      'name': info.name,
      'folder': info.folder,
      'emojis': emojis,
    });
  }

  return {
    'success': true,
    'groups': groups,
    'smilieIdMap': smilieIdMap,
    'insertTextMap': insertTextMap,
  };
}

// ==================== 内部工具 ====================

class _GroupInfo {
  final int id;
  final String name;
  final String folder;
  _GroupInfo({required this.id, required this.name, required this.folder});
}

class _EmojiRaw {
  final String smilieId;
  final String insertText;
  final String filename;
  _EmojiRaw({
    required this.smilieId,
    required this.insertText,
    required this.filename,
  });
}

/// 从 start 找匹配的 ]
int? _findMatchingBracket(String text, int start) {
  int depth = 0;
  for (int i = start; i < text.length; i++) {
    if (text[i] == '[') {
      depth++;
    } else if (text[i] == ']') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return null;
}

/// 将 [[...],[...]] 拆分为每个 [...] 字符串
List<String> _splitInnerArrays(String outerArray) {
  final entries = <String>[];
  var trimmed = outerArray.trim();
  if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) return entries;

  // 去掉外层 [...]
  final inner = trimmed.substring(1, trimmed.length - 1);

  int i = 0;
  while (i < inner.length) {
    // 跳过空白和逗号
    while (i < inner.length && (inner[i] == ' ' || inner[i] == ',')) i++;
    if (i >= inner.length || inner[i] != '[') break;

    final start = i;
    int depth = 0;
    while (i < inner.length) {
      if (inner[i] == '[') {
        depth++;
      } else if (inner[i] == ']') {
        depth--;
        if (depth == 0) {
          entries.add(inner.substring(start, i + 1));
          i++;
          break;
        }
      }
      i++;
    }
  }

  return entries;
}

/// 解析单引号字符串列表 ['a','b','c'] → [a, b, c]
/// 正确处理 \\ 和 \' 转义
List<String> _parseQuotedList(String input) {
  final result = <String>[];
  var trimmed = input.trim();
  if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) return result;

  final inner = trimmed.substring(1, trimmed.length - 1);
  int i = 0;

  while (i < inner.length) {
    // 跳过空白和逗号
    while (i < inner.length && (inner[i] == ' ' || inner[i] == ',')) i++;
    if (i >= inner.length) break;
    if (inner[i] != "'") break;

    i++; // 跳过 '
    final buf = StringBuffer();
    while (i < inner.length) {
      if (inner[i] == '\\') {
        i++;
        if (i < inner.length) {
          buf.write(inner[i]); // 转义字符原样输出
          i++;
        }
      } else if (inner[i] == "'") {
        i++; // 跳过 '
        break;
      } else {
        buf.write(inner[i]);
        i++;
      }
    }
    result.add(buf.toString());
  }

  return result;
}
