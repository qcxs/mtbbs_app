/// 解析验证问答相关响应（纯函数，无网络逻辑）。

/// 从 `action=update` 响应里取出题面。
///
/// 实测响应形如：
/// `var string = '<input name="secqaahash" …>' + sectplcode[0] + '验证问答' +
///  sectplcode[1] + '<input name="secanswer" …>' + … +
///  sectplcode[2] + '吾爱破解论坛的英文缩写是什么？答案：LCG' + sectplcode[3];`
///
/// 题面固定夹在 `sectplcode[2]` 与 `sectplcode[3]` 之间；取不到时返回空串，
/// 由调用方显示「题目加载失败」。
String parseSecqaaQuestion(String body) {
  // 主路径：`sectplcode[2] + '题面'`
  final primary = RegExp(
    r"sectplcode\[2\]\s*\+\s*'((?:[^'\\]|\\.)*)'",
  ).firstMatch(body);
  if (primary != null) return _clean(primary.group(1)!);

  // 兜底：`'题面' + sectplcode[3]`
  final fallback = RegExp(
    r"'((?:[^'\\]|\\.)*)'\s*\+\s*sectplcode\[3\]",
  ).firstMatch(body);
  if (fallback != null) return _clean(fallback.group(1)!);

  return '';
}

/// 从题面里提取站点自带的答案提示。
///
/// 部分站点（如 52pojie）把答案直接写在题目里：`…的英文缩写是什么？答案：LCG`。
/// 取不到时返回空串（UI 不显示「填充答案」）。
String parseSecqaaAnswer(String question) {
  final match = RegExp(r'答案\s*[:：]\s*([^\s，。；,;]+)').firstMatch(question);
  return match?.group(1)?.trim() ?? '';
}

/// 还原 JS 字符串里的转义，并去掉可能混入的 HTML 标签/实体。
String _clean(String raw) {
  var text = raw
      .replaceAll(r"\'", "'")
      .replaceAll(r'\"', '"')
      .replaceAll(r'\\', '\\')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
  return text.trim();
}
