import 'dart:convert';

/// 阅读页 BBCode → 可直接粘贴到编辑器的「纯 BBCode」
///
/// 阅读页的 BBCode 里混有 `[appdata]{"type":…}[/appdata]` 这类 App 私有载荷：
/// 图片附件、文件附件、公式、悬赏/奖励/投票/锁定提示等。Discuz 编辑器不识别
/// appdata，直接复制过去只会留下一串 JSON。这里按类型降级为标准 BBCode：
///
/// - 图片附件 → `[img]url[/img]`（跨站可用的真实地址）
/// - 文件附件 → `[url=url]文件名[/url]`（附件 aid 属于原帖，换帖/换站会失效）
/// - 公式 → `$…$` / `$$…$$`（保留原始 TeX）
/// - 页面装饰（回帖奖励 / 悬赏 / 投票 / 编辑状态 / 锁定提示）→ 丢弃
/// - 未知或损坏的 appdata → 丢弃
String toPlainBbcode(String source) {
  final result = source.replaceAllMapped(
    _appdataRe,
    (m) => _appdataToBbcode(m.group(1)!),
  );
  return result.trim();
}

final _appdataRe = RegExp(r'\[appdata\]([\s\S]*?)\[/appdata\]');

String _appdataToBbcode(String rawJson) {
  Map<String, dynamic> data;
  try {
    data = jsonDecode(rawJson) as Map<String, dynamic>;
  } catch (_) {
    return '';
  }

  switch (data['type']) {
    case 'image_attach':
      final url = data['url']?.toString() ?? '';
      return url.isEmpty ? '' : '[img]$url[/img]';
    case 'attach':
      final url = data['url']?.toString() ?? '';
      final name = _sanitizeLabel(data['name']?.toString() ?? '');
      if (url.isEmpty) return name;
      return '[url=$url]${name.isEmpty ? url : name}[/url]';
    case 'math':
      final tex = data['tex']?.toString() ?? '';
      if (tex.isEmpty) return '';
      final fence = data['display'] == true ? r'$$' : r'$';
      return '$fence$tex$fence';
    default:
      return '';
  }
}

/// 文件名进 `[url=…]标签[/url]`：方括号会截断标签，统一换成全角
String _sanitizeLabel(String name) =>
    name.replaceAll('[', '［').replaceAll(']', '］');
