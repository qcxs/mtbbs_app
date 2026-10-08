import 'package:dio/dio.dart' show DioException;
import 'package:mtbbs/config/build_config.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/parser/bbcode2html.dart';
import 'package:mtbbs/mcp/mcp_types.dart';

/// 出站数据结构组装 —— 工具层所有响应的唯一出口。
///
/// 这里只做两件事：**字段白名单**（丢弃写操作入口与冗余 URL）与
/// **去噪**（丢 null、压平多行时间）。真正的流式脱敏在 `McpSanitizer`。
class McpPayloads {
  McpPayloads._();

  /// 单条帖子正文的**默认**分片上限（字符）
  ///
  /// 超长楼层不再"一截了之"：调用方可用 `bbcode_offset` 续读同一层，
  /// 见 [post] 返回的 `bbcodeTotalChars` / `bbcodeNextOffset`。
  static const int maxBbcodeChars = 6000;

  /// `max_bbcode_chars` 参数允许的上限（调用方按需调大）
  static const int maxBbcodeCharsLimit = 50000;

  /// 默认返回的楼层数上限
  static const int defaultMaxPosts = 10;

  /// 精简输出时剔除的样式标签（与 App「禁用样式标签」共用同一份定义）
  static final Set<String> _styleTagIds = bbcodeStyleTagIds.toSet();

  /// 出站正文的统一处理：默认剔除纯样式标签，[full] 为 true 时返回逐字原文。
  ///
  /// 帖子楼层与编辑器草稿都走这里，保证"默认精简"的口径一致。
  static String bbcodeForAi(String raw, {required bool full}) =>
      full ? raw : stripDisabledBbcodeTags(raw, _styleTagIds);

  // ==================== App / 站点 ====================

  static Map<String, dynamic> appInfo(McpAccountInfoProvider accountInfo) {
    final site = SiteStore.instance.current;
    return {
      'app': 'MTBBS',
      'versionName': BuildConfig.versionName,
      'versionCode': BuildConfig.versionCode,
      'commitHash': BuildConfig.commitHash,
      'site': {
        'name': site.name,
        'host': SiteStore.instance.host,
        'baseUrl': SiteStore.instance.baseUrl,
        'isMobileUA': SiteStore.instance.isMobileUA,
      },
      'account': accountInfo().toJson(),
    };
  }

  static List<Map<String, dynamic>> sites() {
    final store = SiteStore.instance;
    final currentIndex = store.currentIndex;
    return [
      for (var i = 0; i < store.sites.length; i++)
        {
          'name': store.sites[i].name,
          'host': store.sites[i].host,
          'baseUrl': store.sites[i].baseUrl,
          'isCurrent': i == currentIndex,
        },
    ];
  }

  static Map<String, dynamic> forums() {
    final store = SiteStore.instance;
    final forums = store.forums;
    final ordered = <Map<String, dynamic>>[];
    final seen = <String>{};

    // 先按用户自定义顺序，再补上未在顺序表里的版块
    for (final fid in store.defaultForumOrder) {
      final name = forums[fid];
      if (name == null) continue;
      ordered.add({'fid': fid, 'name': name});
      seen.add(fid);
    }
    for (final entry in forums.entries) {
      if (seen.contains(entry.key)) continue;
      ordered.add({'fid': entry.key, 'name': entry.value});
    }
    return {'host': store.host, 'count': ordered.length, 'forums': ordered};
  }

  // ==================== 帖子 ====================

  /// 帖子列表的公共返回结构（forumdisplay 与 guide 结构一致）
  static Map<String, dynamic> threadList(
    Map<String, dynamic> result, {
    required Map<String, dynamic> extra,
  }) {
    final raw = result['threads'];
    final threads = raw is List
        ? raw.map(thread).whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];
    return _dropNulls({
      ...extra,
      'success': result['success'] ?? false,
      if (result['message'] != null) 'message': result['message'],
      'count': threads.length,
      'currentPage': result['currentPage'],
      'totalPages': result['totalPages'],
      // 不是所有列表接口都返回分页信息（如「用户的主题/回复」）。
      // 缺失时**不写** hasMore，否则固定的 false 会让 AI 误以为"已经到底了"。
      if (result['hasMore'] != null) 'hasMore': result['hasMore'],
      'threads': threads,
    });
  }

  // ==================== 用户 ====================

  /// 用户维度列表（好友 / 关注 / 粉丝）的公共返回结构。
  ///
  /// `friend` 与 `follow` 两个 parse 的输出形状一致（`items` + 分页），
  /// 因此共用这一份白名单；`avatar` 图片 URL 对 AI 无意义，直接丢弃。
  static Map<String, dynamic> userList(
    Map<String, dynamic> result, {
    required Map<String, dynamic> extra,
  }) {
    final raw = result['items'];
    final users = raw is List
        ? raw.map(userItem).whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];
    return _dropNulls({
      ...extra,
      'success': result['success'] ?? false,
      if (result['message'] != null) 'message': result['message'],
      // 隐私设置拦截 / 需登录，让 AI 知道"不是没数据，是没权限"
      if (result['privacyBlocked'] == true) 'privacyBlocked': true,
      if (result['loginRequired'] == true) 'loginRequired': true,
      'count': users.length,
      'currentPage': result['currentPage'],
      'totalPages': result['totalPages'],
      if (result['hasMore'] != null) 'hasMore': result['hasMore'],
      'users': users,
    });
  }

  /// 单个用户的字段白名单（好友 / 关注 / 粉丝页的字段并集）
  static Map<String, dynamic>? userItem(dynamic raw) {
    if (raw is! Map) return null;
    return _dropNulls({
      'uid': raw['uid']?.toString(),
      'username': raw['username'],
      'userGroup': raw['userGroup'],
      'credits': raw['credits'],
      'note': raw['note'],
      'hot': raw['hot'],
      'from': raw['from'],
      'followerCount': raw['followerCount'],
      'followingCount': raw['followingCount'],
      'recentAction': raw['recentAction'],
    });
  }

  /// 帖子详情：标题 + 楼层正文，按 [maxPosts] 截断
  ///
  /// [fullBbcode] 为 false（默认）时正文剔除纯样式标签，省 AI 上下文。
  /// 单层正文按 [bbcodeOffset] + [maxChars] 分片，超长楼层可用偏移量续读。
  static Map<String, dynamic> threadDetail(
    Map<String, dynamic> result, {
    required String tid,
    required int maxPosts,
    bool fullBbcode = false,
    int bbcodeOffset = 0,
    int maxChars = maxBbcodeChars,
  }) {
    final rawPosts = result['posts'];
    final all = rawPosts is List ? rawPosts : const <dynamic>[];
    final sliced = all.take(maxPosts).toList();
    final mainPost = result['mainPost'];

    var bodyTruncated = false;
    Map<String, dynamic> buildPost(Map p) {
      final out = post(
        p,
        fullBbcode: fullBbcode,
        offset: bbcodeOffset,
        maxChars: maxChars,
      );
      if (out['bbcodeNextOffset'] != null) bodyTruncated = true;
      return out;
    }

    final mainOut = mainPost is Map ? buildPost(mainPost) : null;
    final posts = [
      for (final p in sliced)
        if (p is Map) buildPost(p),
    ];

    final notes = <String>[];
    if (all.length > sliced.length) {
      notes.add(
        '本页共 ${all.length} 层，已按 max_posts=$maxPosts 截断；'
        '需要后续楼层请提高 max_posts 或继续翻页。',
      );
    }
    if (bodyTruncated) {
      notes.add(
        '部分楼层正文超出 max_bbcode_chars=$maxChars，已分片返回：'
        '各层带 bbcodeNextOffset，用它作为 bbcode_offset 可续读同一层'
        '（可同时提高 max_bbcode_chars，上限 $maxBbcodeCharsLimit）。',
      );
    }

    return _dropNulls({
      'tid': result['tid'] ?? tid,
      'success': result['success'] ?? false,
      if (result['message'] != null) 'message': result['message'],
      'title': result['title'],
      'currentPage': result['currentPage'],
      'totalPages': result['totalPages'],
      'mainPost': mainOut,
      'posts': posts,
      'returnedPosts': posts.length,
      'totalPostsOnPage': all.length,
      'truncated': all.length > sliced.length,
      'bbcodeMode': fullBbcode ? 'full' : 'slim',
      'note': notes.isEmpty ? null : notes.join(' '),
    });
  }

  /// 帖子列表项的字段白名单（丢弃 formhash 类写操作入口与冗余 URL）
  static Map<String, dynamic>? thread(dynamic raw) {
    if (raw is! Map) return null;
    return _dropNulls({
      'tid': raw['threadId']?.toString(),
      'title': raw['title'],
      'author': raw['nickname'],
      'authorUid': raw['uid']?.toString(),
      'board': raw['boardName'],
      'replyTime': _oneLine(raw['time']),
      'likes': raw['likes'],
      'comments': raw['comments'],
      'views': raw['views'],
      'level': raw['level'],
      'summary': raw['summary'],
      'images': raw['images'],
    });
  }

  /// 楼层字段白名单（正文按 [offset] + [maxChars] 分片返回）
  ///
  /// [fullBbcode] 为 false（默认）时剔除纯样式标签（加粗/颜色/字号…），
  /// 只保留有语义的内容标签；需要完整原文时传 true。
  ///
  /// **分片语义**：偏移量作用于"输出后的文本"（精简与完整两种形态长度不同），
  /// 续读时必须沿用同一 `full_bbcode`，故响应回显 `bbcodeMode` 供 AI 对齐。
  static Map<String, dynamic> post(
    Map post, {
    bool fullBbcode = false,
    int offset = 0,
    int maxChars = maxBbcodeChars,
  }) {
    final raw = post['bbcode']?.toString() ?? '';
    final text = bbcodeForAi(raw, full: fullBbcode);
    final total = text.length;
    final start = offset.clamp(0, total);
    final end = (start + maxChars).clamp(start, total);
    final hasMore = end < total;
    final segment = text.substring(start, end);

    return _dropNulls({
      'pid': post['pid'],
      'floor': post['floor'],
      'floorLabel': post['floorLabel'],
      'isOp': post['isOp'],
      'uid': post['uid'],
      'username': post['username'],
      'usergroup': post['usergroup'],
      'postTime': post['postTime'],
      'source': post['source'],
      'bbcode': hasMore
          ? '$segment\n…（本层正文共 $total 字，本次返回第 $start-$end 字；'
                '继续读取请传 bbcode_offset=$end）'
          : segment,
      'bbcodeTotalChars': total,
      if (hasMore) 'bbcodeNextOffset': end,
      'rating': post['rating'],
    });
  }

  // ==================== 错误 ====================

  /// 把 HTTP 错误翻译成可读提示（不向 AI 暴露 Dio 内部异常结构）
  static String describeDioError(DioException e) {
    final status = e.response?.statusCode;
    return switch (status) {
      404 => '目标不存在：帖子/用户可能已被删除，或 ID（tid/uid）有误（HTTP 404）',
      403 => '没有访问权限（HTTP 403）：该内容可能需要登录或权限不足',
      401 => '登录态已失效（HTTP 401）：请在 App 内重新登录后重试',
      null => '网络请求失败：${e.message ?? '无法连接论坛'}',
      _ => '论坛返回异常状态码 HTTP $status',
    };
  }

  // ==================== 内部工具 ====================

  /// 去掉值为 null 的键，减少 AI 上下文噪音（缺字段即代表无值）
  static Map<String, dynamic> _dropNulls(Map<String, dynamic> map) =>
      map..removeWhere((_, value) => value == null);

  /// 论坛的时间字段常带换行（`半小时前\n 来自 XX`），压成单行便于阅读
  static String? _oneLine(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    return text.replaceAll(RegExp(r'\s+'), ' ');
  }
}
