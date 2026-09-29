/// BBCode 源码的「行」坐标 —— 编辑区光标 ↔ 锚点的地基。
///
/// 为什么还需要"行"：编辑区的标记要落在**文本行**上（`RenderEditable` 只认
/// 字符偏移），而锚点是源码区间。`anchor.line` 给出"这个锚点的第一个字在第
/// 几行"，编辑区据此向 `RenderEditable` 要那一行的真实光标矩形。
///
/// 注意：这里只做**纯粹的行切分与偏移换算**。跨"编辑区 ↔ 预览区"的对应关系
/// 一律由锚点（见 `bbcode_anchors.dart`）承担 —— 那是结构身份，不是坐标。
library;

/// 一行源码：起始偏移 + 行内容（不含换行符）
typedef BbSourceLine = ({int start, String text});

/// 把源码切成行（末尾无换行时最后一行也算一行）
List<BbSourceLine> bbcodeSourceLines(String source) {
  final lines = <BbSourceLine>[];
  var start = 0;
  for (var i = 0; i <= source.length; i++) {
    if (i == source.length || source[i] == '\n') {
      lines.add((start: start, text: source.substring(start, i)));
      start = i + 1;
    }
  }
  return lines;
}

/// 光标偏移落在第几行（0 基）。
///
/// 偏移为负或超出末尾时分别钳到首行 / 末行，保证调用方不需要处理越界。
int bbcodeLineIndexOf(String source, int offset) {
  if (offset <= 0) return 0;
  final clamped = offset > source.length ? source.length : offset;
  var line = 0;
  for (var i = 0; i < clamped; i++) {
    if (source[i] == '\n') line++;
  }
  return line;
}

/// 该行的「可见文本」—— 只保留渲染成文字的部分。
///
/// 两步：
/// 1. **整段删掉渲染成非文本的标签**（图片 / 附件 / 音视频 / appdata）：
///    它们没有对应文字，留着反而会让人以为该锚点有内容
/// 2. 删掉其余 `[tag]` 标记，只留下文字
///
/// 结果可能为空（空行、纯图片行）——这是**正常**结果，调用方据此退回类型名。
String bbcodeLineVisibleText(String line) {
  var out = line.replaceAll(
    RegExp(
      r'\[(img|attachimg|attach|audio|flash|media|video|appdata)\][\s\S]*?'
      r'\[/\1\]',
      caseSensitive: false,
    ),
    '',
  );
  out = out.replaceAll(RegExp(r'\[hr\]', caseSensitive: false), '');
  out = out.replaceAll(RegExp(r'\[[^\]]*\]'), '');
  return out.trim();
}
