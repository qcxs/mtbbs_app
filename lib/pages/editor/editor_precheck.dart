/// 编辑器「发布前本地预校验」的纯逻辑。
///
/// 与 UI 解耦：这里只做判定与文本处理，弹窗与写回控制器由编辑器负责，
/// 便于单测（`test/editor_precheck_test.dart`）。
library;

/// 统计不兼容 Emoji —— 码点 > U+FFFF 的字符（4 字节 UTF-8）。
///
/// 站点按 3 字节以内的 UTF-8 处理正文，这类字符提交后会被截断，
/// 因此编辑器在发布前拦截（顶栏提示「输入内容包含不兼容的 Emoji」同源，
/// 见 `editor_hints.dart`）。
int countIncompatibleEmoji(String text) {
  var count = 0;
  for (final rune in text.runes) {
    if (rune > 0xFFFF) count++;
  }
  return count;
}

/// 去掉全部不兼容 Emoji，返回新文本；无 Emoji 时原样返回。
String stripIncompatibleEmoji(String text) {
  if (countIncompatibleEmoji(text) == 0) return text;
  return String.fromCharCodes(text.runes.where((r) => r <= 0xFFFF));
}

/// 找出「已上传但未插入正文」的图片 / 附件 aid。
///
/// 判定与图片 / 附件面板一致：正文里出现 `[attachimg]{aid}[/attachimg]`
/// 或 `[attach]{aid}[/attach]` 即视为已插入（见 `image_picker_sheet` /
/// `attachment_picker_sheet` 的 `_isInserted`）。
({Set<String> images, Set<String> attachments}) uninsertedMedia({
  required String content,
  required Iterable<String> imageAids,
  required Iterable<String> attachmentAids,
}) {
  return (
    images: imageAids
        .where((aid) => aid.isNotEmpty && !content.contains('[attachimg]$aid[/attachimg]'))
        .toSet(),
    attachments: attachmentAids
        .where((aid) => aid.isNotEmpty && !content.contains('[attach]$aid[/attach]'))
        .toSet(),
  );
}
