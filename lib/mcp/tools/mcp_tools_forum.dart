import 'package:mcp_dart/mcp_dart.dart';
import 'package:mtbbs/api/forum/forumdisplay/export.dart' as forumdisplay;
import 'package:mtbbs/api/forum/guide/export.dart' as guide;
import 'package:mtbbs/api/forum/online/export.dart' as online;
import 'package:mtbbs/api/forum/ranklist/export.dart' as ranklist;
import 'package:mtbbs/api/forum/rss/export.dart' as rss;
import 'package:mtbbs/api/forum/search/export.dart' as search;
import 'package:mtbbs/api/forum/viewthread/detail/export.dart' as viewthread;
import 'package:mtbbs/api/group/groupindex/export.dart' as groups;
import 'package:mtbbs/api/home/space/export.dart' as space;
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/mcp/mcp_scope.dart';
import 'package:mtbbs/mcp/mcp_types.dart';
import 'package:mtbbs/mcp/tools/mcp_payloads.dart';
import 'package:mtbbs/mcp/tools/mcp_tool_definition.dart';
import 'package:mtbbs/models/thread_snapshot.dart';
import 'package:mtbbs/services/thread_cache_service.dart';

/// 论坛公开数据组工具（`McpToolGroup.publicData`）
///
/// 全部走现有 `lib/api/**/export.dart`，共用 `McpScope.effectiveDio`
/// （因此登录态下的可见范围与 App 内一致），本层不新增解析逻辑。
List<McpToolDefinition> forumTools(McpAccountInfoProvider accountInfo) => [
  McpToolDefinition(
    name: 'list_forums',
    group: McpToolGroup.publicData,
    description: '列出当前站点的版块（fid 与版块名），用于后续 list_forum_threads 传入 fid。',
    properties: const {},
    network: false, // 读站点缓存里的版块表，不发请求
    run: (args) async => McpPayloads.forums(),
  ),
  McpToolDefinition(
    name: 'list_forum_threads',
    group: McpToolGroup.publicData,
    description: '按版块列出帖子列表（分页）。fid 由 list_forums 获取。',
    properties: {
      'fid': JsonSchema.string(description: '版块 ID，来自 list_forums'),
      'page': JsonSchema.integer(
        minimum: 1,
        maximum: 200,
        description: '页码，默认 1',
      ),
    },
    requiredArgs: const ['fid'],
    mobileSupported: true, // 版块列表：克米移动卡片 / 标准 PC 表格，解析器工厂两套通吃
    run: (args) async {
      final fid = McpArgs.requireStr(args, 'fid');
      final page = McpArgs.integer(args, 'page', fallback: 1, min: 1, max: 200);
      final result = await forumdisplay.getForumThreads(
        McpScope.effectiveDio,
        fid: fid,
        page: page,
      );
      return McpPayloads.threadList(result, extra: {'fid': fid});
    },
  ),
  McpToolDefinition(
    name: 'list_guide_threads',
    group: McpToolGroup.publicData,
    description:
        '列出导读（全站）帖子，view 可选：newthread 最新发表 / hot 热门 / new 最新回复 / digest 精华 / sofa 抢沙发 / my 我的帖子。',
    properties: {
      'view': JsonSchema.string(
        description: '导读视图，默认 newthread',
        enumValues: const ['newthread', 'hot', 'new', 'digest', 'sofa', 'my'],
      ),
      'page': JsonSchema.integer(
        minimum: 1,
        maximum: 200,
        description: '页码，默认 1',
      ),
    },
    mobileSupported: true, // 导读：移动卡片 / PC 表格
    run: (args) async {
      final view = McpArgs.str(args, 'view', fallback: 'newthread');
      final page = McpArgs.integer(args, 'page', fallback: 1, min: 1, max: 200);
      final result = await guide.getThreadList(
        McpScope.effectiveDio,
        view: view,
        page: page,
      );
      return McpPayloads.threadList(result, extra: {'view': view});
    },
  ),
  McpToolDefinition(
    name: 'search_forum_threads',
    group: McpToolGroup.publicData,
    description:
        '按关键词站内搜索帖子（标题匹配），返回帖子列表与 searchId。'
        '首次传 keyword；翻页时把上次返回的 searchId 回传并传 page（回传 searchId 不会新建搜索）。'
        '注意：站点对新搜索有频率限制（短时间内重复搜索会失败并返回"搜索过于频繁/稍后再试"），'
        '无结果时返回 noMatch=true，需登录时返回 loginRequired=true。',
    properties: {
      'keyword': JsonSchema.string(description: '搜索关键词；首次搜索必填'),
      'search_id': JsonSchema.string(
        description: '上次搜索返回的 searchId；翻页时传它（此时 keyword 可省略）',
      ),
      'page': JsonSchema.integer(
        minimum: 1,
        maximum: 200,
        description: '页码，默认 1',
      ),
    },
    mobileSupported: true, // 搜索：移动克米 / 桌面 Discuz，两套解析器
    run: (args) async {
      final keyword = McpArgs.str(args, 'keyword');
      final searchId = McpArgs.str(args, 'search_id');
      final page = McpArgs.integer(args, 'page', fallback: 1, min: 1, max: 200);
      if (keyword.isEmpty && searchId.isEmpty) {
        throw ArgumentError(
          'keyword 与 search_id 至少传一个（首次搜索传 keyword，翻页传 search_id）',
        );
      }
      final result = await search.searchThreads(
        McpScope.effectiveDio,
        keyword: keyword,
        page: page,
        searchId: searchId.isEmpty ? null : searchId,
        // 跨站点时按目标站点编码查询参数（如 GBK 站点），未跨站传 null 走全局
        charset: McpScope.current?.charset,
      );
      return McpPayloads.threadList(
        result,
        extra: {
          if (keyword.isNotEmpty) 'keyword': keyword,
          if (result['searchId'] != null) 'searchId': result['searchId'],
          if (result['noMatch'] == true) 'noMatch': true,
          if (result['loginRequired'] == true) 'loginRequired': true,
        },
      );
    },
  ),
  McpToolDefinition(
    name: 'get_thread_detail',
    group: McpToolGroup.publicData,
    description:
        '读取帖子详情：标题 + 楼层正文。正文默认返回**精简 BBCode**——'
        '已剔除加粗/斜体/下划线/颜色/字号/字体/背景色/对齐等纯样式标签（保留删除线，'
        '因其带语义），省上下文。需要逐字原文（如样式、引用格式）时传 full_bbcode=true。'
        '默认只返回前 ${McpPayloads.defaultMaxPosts} 层（更多请提高 max_posts 或翻页）。'
        '单层正文超过 max_bbcode_chars（默认 ${McpPayloads.maxBbcodeChars} 字，上限 '
        '${McpPayloads.maxBbcodeCharsLimit}）时分片返回，该层会带 bbcodeNextOffset，'
        '用它作为 bbcode_offset 再次调用即可续读同一层（务必沿用相同的 full_bbcode）。'
        '数据源默认 source=auto：优先使用 App 的帖子缓存（不发 HTTP），'
        '对时效性要求高时传 source=network 强制联网。',
    properties: {
      'tid': JsonSchema.string(description: '帖子 ID（tid）'),
      'page': JsonSchema.integer(
        minimum: 1,
        maximum: 200,
        description: '页码，默认 1',
      ),
      'source': JsonSchema.string(
        description:
            '数据来源：auto（默认，有效缓存优先、未命中再联网）/ network（强制联网）/ '
            'cache（只读缓存，未命中时返回 cacheMiss=true 而不发请求）',
        enumValues: const ['auto', 'network', 'cache'],
      ),
      'max_posts': JsonSchema.integer(
        minimum: 1,
        maximum: 50,
        description: '最多返回多少层，默认 ${McpPayloads.defaultMaxPosts}',
      ),
      'full_bbcode': JsonSchema.boolean(
        description: '是否返回完整 BBCode（含样式标签）。默认 false，精简版更省上下文。',
      ),
      'bbcode_offset': JsonSchema.integer(
        minimum: 0,
        maximum: 10000000,
        description:
            '正文起始字符偏移，默认 0。用于续读超长楼层——'
            '取上一次响应中该层的 bbcodeNextOffset。',
      ),
      'max_bbcode_chars': JsonSchema.integer(
        minimum: 1,
        maximum: McpPayloads.maxBbcodeCharsLimit,
        description:
            '每层正文最多返回多少字，默认 ${McpPayloads.maxBbcodeChars}，'
            '上限 ${McpPayloads.maxBbcodeCharsLimit}',
      ),
    },
    requiredArgs: const ['tid'],
    run: (args) async {
      final tid = McpArgs.requireStr(args, 'tid');
      final page = McpArgs.integer(args, 'page', fallback: 1, min: 1, max: 200);
      final maxPosts = McpArgs.integer(
        args,
        'max_posts',
        fallback: McpPayloads.defaultMaxPosts,
        min: 1,
        max: 50,
      );
      final fullBbcode = McpArgs.boolean(args, 'full_bbcode');
      final bbcodeOffset = McpArgs.integer(
        args,
        'bbcode_offset',
        fallback: 0,
        min: 0,
        max: 10000000,
      );
      final maxChars = McpArgs.integer(
        args,
        'max_bbcode_chars',
        fallback: McpPayloads.maxBbcodeChars,
        min: 1,
        max: McpPayloads.maxBbcodeCharsLimit,
      );
      final source = McpArgs.str(args, 'source', fallback: 'auto').toLowerCase();
      if (!const {'auto', 'network', 'cache'}.contains(source)) {
        throw ArgumentError(
          '不支持的 source=$source，可用：auto / network / cache',
        );
      }
      if (source != 'network') {
        final viewer = McpScope.effectiveUid;
        final hit = await _readCachedThread(
          tid: tid,
          viewer: viewer,
          page: page,
          requireUnexpired: source == 'auto',
        );
        if (hit != null) {
          return McpPayloads.threadDetail(
            _cachedResult(hit, page),
            tid: tid,
            maxPosts: maxPosts,
            fullBbcode: fullBbcode,
            bbcodeOffset: bbcodeOffset,
            maxChars: maxChars,
            extra: _cacheExtra(hit, page),
          );
        }
        if (source == 'cache') {
          return _cacheMiss(
            tid: tid,
            page: page,
            metas: await _cachedMetas(tid: tid, viewer: viewer),
          );
        }
      }
      final result = await viewthread.getThreadDetail(
        McpScope.effectiveDio,
        tid: tid,
        page: page,
      );
      return McpPayloads.threadDetail(
        result,
        tid: tid,
        maxPosts: maxPosts,
        fullBbcode: fullBbcode,
        bbcodeOffset: bbcodeOffset,
        maxChars: maxChars,
        extra: const {'source': 'network'},
      );
    },
  ),
  McpToolDefinition(
    name: 'get_user_profile',
    group: McpToolGroup.publicData,
    description:
        '获取用户公开资料（昵称、用户组、签名、发帖数等）。联系方式、实名与 IP 已被剥离。'
        'uid 与 username 至少传一个。',
    properties: {
      'uid': JsonSchema.string(description: '用户 UID'),
      'username': JsonSchema.string(description: '用户名'),
    },
    mobileSupported: true, // 用户空间：克米移动 ↔ 标准 PC，parse 按 DOM 分流
    run: (args) async {
      final uid = McpArgs.str(args, 'uid');
      final username = McpArgs.str(args, 'username');
      if (uid.isEmpty && username.isEmpty) {
        throw ArgumentError('uid 与 username 至少传一个');
      }
      final result = await space.getUserProfile(
        McpScope.effectiveDio,
        uid: uid,
        username: username,
      );
      return {
        'success': result['success'] ?? false,
        if (result['message'] != null) 'message': result['message'],
        if (result['profile'] != null) 'profile': result['profile'],
      };
    },
  ),
  McpToolDefinition(
    name: 'get_ranklist',
    group: McpToolGroup.publicData,
    description: '获取论坛排行榜：type=thread 帖子 / member 用户 / forum 版块。',
    properties: {
      'type': JsonSchema.string(
        description: '排行类型：thread（帖子）/ member（用户）/ forum（版块），默认 thread',
      ),
      'view': JsonSchema.string(
        description:
            '视图。thread: replies/views/sharetimes/favtimes/heats；'
            'member: beauty/handsome/credit/friendnum/invite/post/onlinetime；'
            'forum: threads/posts/today',
      ),
      'orderby': JsonSchema.string(
        description: '排序方式（仅 thread 有效）：thisweek/thismonth/today/all，默认 thisweek',
      ),
    },
    requiredArgs: const ['view'],
    run: (args) async {
      final type = McpArgs.str(args, 'type', fallback: 'thread');
      final view = McpArgs.requireStr(args, 'view');
      final orderby = McpArgs.str(args, 'orderby', fallback: 'thisweek');
      return ranklist.getRanklist(
        McpScope.effectiveDio,
        type: type,
        view: view,
        orderby: orderby,
      );
    },
  ),
  McpToolDefinition(
    name: 'get_online_users',
    group: McpToolGroup.publicData,
    description: '获取当前在线会员与统计信息。',
    properties: const {},
    run: (args) async => online.fetchOnlineUsers(McpScope.effectiveDio),
  ),
  McpToolDefinition(
    name: 'get_rss_feed',
    group: McpToolGroup.publicData,
    description: '获取站点 RSS 最新条目（标题、链接、发布时间）。',
    properties: const {},
    run: (args) async => rss.getRssFeed(McpScope.effectiveDio),
  ),
  McpToolDefinition(
    name: 'list_groups',
    group: McpToolGroup.publicData,
    description:
        '列出站点的圈子（Discuz 群组）首页：推荐圈子、圈子分类（含各分类下的圈子预览）与积分排行。'
        '读某个圈子的帖子用 list_forum_threads（fid 传圈子的 gid）。',
    properties: const {},
    run: (args) async => McpPayloads.groupIndex(await groups.fetchGroupIndex(McpScope.effectiveDio)),
  ),
  McpToolDefinition(
    name: 'list_group_forums',
    group: McpToolGroup.publicData,
    description: '列出某个圈子分类（gid）下的圈子列表（分页）。gid 来自 list_groups 的 categories。',
    properties: {
      'gid': JsonSchema.string(description: '圈子分类 ID，来自 list_groups'),
      'page': JsonSchema.integer(
        minimum: 1,
        maximum: 200,
        description: '页码，默认 1',
      ),
    },
    requiredArgs: const ['gid'],
    run: (args) async {
      final gid = McpArgs.requireStr(args, 'gid');
      final page = McpArgs.integer(args, 'page', fallback: 1, min: 1, max: 200);
      final result = await groups.fetchCategoryGroups(
        McpScope.effectiveDio,
        gid: gid,
        page: page,
      );
      return McpPayloads.groupCategory(result);
    },
  ),
];

// ==================== 帖子缓存（source=auto / cache） ====================

class _CachedThreadHit {
  const _CachedThreadHit({required this.snapshot, required this.meta});

  final ThreadSnapshot snapshot;
  final ThreadSnapshotMeta meta;
}

/// 某帖在当前站点、当前账号下可见的缓存索引（自动 + 离线），新的在前。
///
/// 缓存库损坏或读取异常时降级为空：不能让本地缓存问题阻断联网读取。
Future<List<ThreadSnapshotMeta>> _cachedMetas({
  required String tid,
  required String viewer,
}) async {
  final service = ThreadCacheService.instance;
  if (service.isDisabled) return const [];
  try {
    return await service.snapshotsForThread(
      host: McpScope.effectiveHost,
      tid: tid,
      viewer: viewer,
    );
  } catch (e) {
    AppLogger.w('MCP', '读取帖子缓存索引失败: $e');
    return const [];
  }
}

/// 从新到旧挑一份可用快照。
///
/// 第 1 页只要快照存在即可（至少含楼主帖）；更深页要求该页评论确实缓存过。
Future<_CachedThreadHit?> _readCachedThread({
  required String tid,
  required String viewer,
  required int page,
  required bool requireUnexpired,
}) async {
  final metas = await _cachedMetas(tid: tid, viewer: viewer);
  final now = DateTime.now();
  for (final meta in metas) {
    if (requireUnexpired && meta.isExpiredAt(now)) continue;
    if (page > 1 && !meta.cachedPages.contains(page)) continue;
    try {
      final snapshot = await ThreadCacheService.instance.readSnapshot(
        meta.key,
      );
      if (snapshot == null) continue;
      return _CachedThreadHit(snapshot: snapshot, meta: meta);
    } catch (e) {
      AppLogger.w('MCP', '读取帖子缓存失败(${meta.key}): $e');
    }
  }
  return null;
}

/// 把快照还原成与联网结果同形的输入，复用 `McpPayloads.threadDetail`
Map<String, dynamic> _cachedResult(_CachedThreadHit hit, int page) {
  final snapshot = hit.snapshot;
  final posts = snapshot.commentPages[page];
  return {
    'tid': snapshot.tid,
    'success': true,
    'title': snapshot.title,
    'currentPage': page,
    'totalPages': snapshot.totalPages,
    'mainPost': snapshot.mainPost.toMap(),
    'posts': posts == null
        ? <Map<String, dynamic>>[]
        : [for (final p in posts) p.toMap()],
  };
}

/// 缓存命中时附加的溯源信息：AI 可据此判断内容是否够新、分页是否完整
Map<String, dynamic> _cacheExtra(_CachedThreadHit hit, int page) {
  final meta = hit.meta;
  final stale = meta.isExpiredAt(DateTime.now());
  final pageCached = page == 1 || meta.cachedPages.contains(page);
  return {
    'source': 'cache',
    'cache': {
      'kind': meta.kind.name,
      'stale': stale,
      'cachedPages': meta.cachedPages,
      'totalPages': meta.totalPages,
      'approxBytes': meta.approxBytes,
      if (meta.lastVisitedAt != null)
        'lastVisitedAt': meta.lastVisitedAt!.toIso8601String(),
      if (meta.savedAt != null) 'savedAt': meta.savedAt!.toIso8601String(),
      if (meta.expiresAt != null)
        'expiresAt': meta.expiresAt!.toIso8601String(),
    },
    'cacheNote':
        '${[
          '内容来自本地缓存，可能不含最新回复',
          if (stale) '且已超过自动缓存有效期',
          if (!pageCached) '该页评论尚未缓存，仅返回楼主帖',
          '需要最新内容请传 source=network',
        ].join('；')}。',
  };
}

/// `source=cache` 未命中：不发请求，直接告诉 AI 哪些页有缓存
Map<String, dynamic> _cacheMiss({
  required String tid,
  required int page,
  required List<ThreadSnapshotMeta> metas,
}) {
  final pages = <int>{
    for (final meta in metas) ...meta.cachedPages,
  }.toList()..sort();
  return {
    'tid': tid,
    'success': false,
    'source': 'cache',
    'cacheMiss': true,
    'requestedPage': page,
    'cacheAvailablePages': pages,
    if (metas.isEmpty) 'cacheEmpty': true,
    'message':
        '该帖第 $page 页没有可用缓存；请改用 source=network 或 source=auto 重新读取。',
  };
}
