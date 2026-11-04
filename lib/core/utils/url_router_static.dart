part of 'url_router.dart';

/// 解析伪静态格式的 URL（帖子 / 用户 / 板块 / 圈子）。
UrlRouteResult? _matchPseudoStatic(
  String url,
  Map<String, String> query,
  _SiteRef site,
) {
  // thread-{tid}-{page}-{ordertype}.html
  // 示例：thread-169246.html → tid=169246（无 page）
  //       thread-169246-5-1.html → tid=169246, page=5
  //       支持外部 ?page=N 覆盖，如 thread-169246-1-1.html?page=2
  final threadFull = RegExp(r'thread-(\d+)-(\d+)').firstMatch(url);
  if (threadFull != null) {
    final tid = threadFull.group(1)!;
    final pathPage = int.tryParse(threadFull.group(2)!) ?? 1;
    // 外部查询参数 page 优先级高于路径中的 page
    final page = _resolvePage(query['page'], fallback: pathPage);
    return _r(site, '帖子详情', _threadPath(tid, page));
  }
  // thread-{tid}.html（无 page/ordertype 的简写格式）
  final threadSimple = RegExp(r'thread-(\d+)').firstMatch(url);
  if (threadSimple != null) {
    final tid = threadSimple.group(1)!;
    final page = _resolvePage(query['page']);
    return _r(site, '帖子详情', _threadPath(tid, page));
  }

  // space-uid-456.html
  final spaceMatch = RegExp(r'space-uid-(\d+)').firstMatch(url);
  if (spaceMatch != null) {
    final uid = spaceMatch.group(1)!;
    return _r(site, '用户主页', '/user/$uid');
  }

  // forum-{fid}-{page}.html
  // 示例：forum-42-1.html → fid=42, page=1
  final forumFull = RegExp(r'forum-(\d+)-(\d+)').firstMatch(url);
  if (forumFull != null) {
    final fid = forumFull.group(1)!;
    final page = int.tryParse(forumFull.group(2)!) ?? 1;
    final pageSuffix = page > 1 ? '&page=$page' : '';
    return _r(site, '板块', '/forum?fid=$fid$pageSuffix');
  }
  // forum-{fid}.html（无 page 的简写格式）
  final forumSimple = RegExp(r'forum-(\d+)').firstMatch(url);
  if (forumSimple != null) {
    final fid = forumSimple.group(1)!;
    return _r(site, '板块', '/forum?fid=$fid');
  }

  // group-{gid}-{page}.html（圈子内容，只读讨论区）
  final groupMatch = RegExp(r'group-(\d+)').firstMatch(url);
  if (groupMatch != null) {
    final gid = groupMatch.group(1)!;
    return _r(site, '圈子', '/groups/content?gid=$gid');
  }

  return null;
}

/// 解析站内搜索：search.php?mod=forum&srchtxt=关键词[&srchfilter=digest]
UrlRouteResult? _matchSearchPhp(
  String path,
  Map<String, String> query,
  _SiteRef site,
) {
  if (!path.endsWith('search.php')) return null;
  final kw = query['srchtxt'] ?? query['kw'] ?? query['keyword'] ?? '';
  if (kw.isNotEmpty) {
    final filter = query['srchfilter'] ?? '';
    final params = <String, String>{
      'kw': kw,
      if (filter.isNotEmpty) 'filter': filter,
    };
    final qs =
        '?${params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';
    return _r(site, '搜索「$kw」', '/search/result$qs');
  }
  return _r(site, '搜索（缺少关键词）', null);
}
