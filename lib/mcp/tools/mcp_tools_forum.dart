import 'package:mcp_dart/mcp_dart.dart';
import 'package:mtbbs/api/forum/forumdisplay/export.dart' as forumdisplay;
import 'package:mtbbs/api/forum/guide/export.dart' as guide;
import 'package:mtbbs/api/forum/online/export.dart' as online;
import 'package:mtbbs/api/forum/ranklist/export.dart' as ranklist;
import 'package:mtbbs/api/forum/rss/export.dart' as rss;
import 'package:mtbbs/api/forum/search/export.dart' as search;
import 'package:mtbbs/api/forum/viewthread/detail/export.dart' as viewthread;
import 'package:mtbbs/api/home/space/export.dart' as space;
import 'package:mtbbs/mcp/mcp_types.dart';
import 'package:mtbbs/mcp/tools/mcp_payloads.dart';
import 'package:mtbbs/mcp/tools/mcp_tool_definition.dart';
import 'package:mtbbs/services/api_service.dart';

/// 论坛公开数据组工具（`McpToolGroup.publicData`）
///
/// 全部走现有 `lib/api/**/export.dart`，共用 `ApiService().dio`
/// （因此登录态下的可见范围与 App 内一致），本层不新增解析逻辑。
List<McpToolDefinition> forumTools() => [
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
    run: (args) async {
      final fid = McpArgs.requireStr(args, 'fid');
      final page = McpArgs.integer(args, 'page', fallback: 1, min: 1, max: 200);
      final result = await forumdisplay.getForumThreads(
        ApiService().dio,
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
    run: (args) async {
      final view = McpArgs.str(args, 'view', fallback: 'newthread');
      final page = McpArgs.integer(args, 'page', fallback: 1, min: 1, max: 200);
      final result = await guide.getThreadList(
        ApiService().dio,
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
        ApiService().dio,
        keyword: keyword,
        page: page,
        searchId: searchId.isEmpty ? null : searchId,
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
        '用它作为 bbcode_offset 再次调用即可续读同一层（务必沿用相同的 full_bbcode）。',
    properties: {
      'tid': JsonSchema.string(description: '帖子 ID（tid）'),
      'page': JsonSchema.integer(
        minimum: 1,
        maximum: 200,
        description: '页码，默认 1',
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
      final result = await viewthread.getThreadDetail(
        ApiService().dio,
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
    run: (args) async {
      final uid = McpArgs.str(args, 'uid');
      final username = McpArgs.str(args, 'username');
      if (uid.isEmpty && username.isEmpty) {
        throw ArgumentError('uid 与 username 至少传一个');
      }
      final result = await space.getUserProfile(
        ApiService().dio,
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
        ApiService().dio,
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
    run: (args) async => online.fetchOnlineUsers(ApiService().dio),
  ),
  McpToolDefinition(
    name: 'get_rss_feed',
    group: McpToolGroup.publicData,
    description: '获取站点 RSS 最新条目（标题、链接、发布时间）。',
    properties: const {},
    run: (args) async => rss.getRssFeed(ApiService().dio),
  ),
];
