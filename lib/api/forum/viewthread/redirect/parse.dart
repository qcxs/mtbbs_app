/// 解析跳转定位接口的重定向链，返回最终落点。
///
/// [locations] 为 `Response.redirects` 里的 Location（按发生顺序）。
/// 成功时一定带 `page`（Discuz 对可解析的楼层/回复会显式给页码，含第 1 页）；
/// 只有落到帖子页却没有页码时，才说明楼层超出范围。
///
/// 返回：
/// - 成功：`{success: true, tid, page, pid, authorid}`
/// - 失败：`{success: false, reason: 'no_redirect' | 'floor_not_found', message}`
Map<String, dynamic> parseRedirectLocations(
  List<String> locations,
  int statusCode,
) {
  for (final href in locations.reversed) {
    final uri = Uri.tryParse(href.trim());
    if (uri == null) continue;
    final query = uri.queryParameters;
    final page = int.tryParse(query['page'] ?? '');
    if (page == null) continue;
    return {
      'success': true,
      'tid': query['tid'] ?? '',
      'page': page,
      'pid': _pidOf(uri),
      'authorid': query['authorid'] ?? '',
    };
  }

  if (locations.isEmpty) {
    return {
      'success': false,
      'reason': 'no_redirect',
      'message': '无重定向（HTTP $statusCode）',
    };
  }

  final last = Uri.tryParse(locations.last.trim());
  final query = last?.queryParameters ?? const <String, String>{};
  final reachedThread =
      last != null && (query['mod'] == 'viewthread' || last.path.contains('thread-'));
  return {
    'success': false,
    'reason': reachedThread ? 'floor_not_found' : 'no_redirect',
    'message': reachedThread ? '楼层不存在' : '未落到帖子页（HTTP $statusCode）',
  };
}

/// Discuz 的 Location 用 `#pid11932686` 标记具体回复
String _pidOf(Uri uri) {
  final match = RegExp(r'pid(\d+)').firstMatch(uri.fragment);
  return match?.group(1) ?? '';
}
