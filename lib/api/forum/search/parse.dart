import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/core/parser/thread_parser.dart';
import 'package:mtbbs/core/app/page_helper.dart';

/// 站内搜索结果响应解析
///
/// 从完整 HTML 页面提取帖子列表与分页信息，复用帖子列表解析器工厂
/// （移动克米卡片 → ComiisCardParser；桌面搜索结果 → DiscuzSearchParser）。
///
/// 返回 JSON 结构：
/// {
///   "success": true,
///   "threads": [{...}, ...],
///   "count": 20,
///   "currentPage": 1,
///   "totalPages": 25,
///   "hasMore": true,
///   "noMatch": false,
///   "_health": {...}
/// }

/// 列表容器特征：
/// - 桌面搜索结果：`#threadlist li.pbw`
/// - 移动克米卡片：`[class*="forumlist_li"]`
/// - 通用兜底：`#threadlist`
const _kListContainerSelector = 'li.pbw, [class*="forumlist_li"], #threadlist';

Map<String, dynamic> parseResponse(String body, int statusCode) {
  final pre = prepareDoc(body, statusCode);
  if (pre.error != null) return pre.error!;
  final doc = pre.doc!;

  final pagination = extractPagination(doc);
  final hasList = doc.querySelector(_kListContainerSelector) != null;

  // 登录页 / Discuz 消息页兜底。
  // 站点可禁止游客搜索：移动端会 302 到 comiis 登录页（title「登录」，且**没有**
  // `input[name=loginsubmit]`），PC 端渲染消息页（title「提示信息」）；两者都会绕过
  // prepareDoc 的统一检测，落到下面按"无结果"处理，把"需登录/无权限"误报成"没有找到匹配结果"。
  final pageTitle = doc.querySelector('title')?.text ?? '';
  final isLoginPage =
      pageTitle.contains('登录') ||
      doc.querySelector(
            'body.pg_logging, #loginform, input[name="loginsubmit"]',
          ) !=
          null;
  final isMessagePage =
      pageTitle.contains('提示信息') || doc.getElementById('messagetext') != null;
  if (isLoginPage || isMessagePage) {
    final msg = extractElementText(doc.getElementById('messagetext'));
    final guest = RegExp(r"""discuz_uid\s*=\s*['"]?0['"]?""").hasMatch(body);
    return {
      'success': false,
      'message': msg.isNotEmpty
          ? msg
          : (isLoginPage ? '搜索需要登录' : '搜索被拒绝，请确认有搜索权限'),
      'loginRequired': isLoginPage || guest,
    };
  }

  // 没有列表容器 = 本次搜索无结果（Discuz 空结果页只渲染提示文案，不渲染列表）
  if (!hasList) {
    return {
      'success': true,
      'threads': <Map<String, dynamic>>[],
      'count': 0,
      'currentPage': pagination['currentPage'] ?? 1,
      'totalPages': pagination['totalPages'] ?? 1,
      'hasMore': false,
      'noMatch': true,
      '_health': const {'parser': 'skipped', 'missing': <String>[]},
    };
  }

  final info = parseThreadListInfo(body);
  final threads = info.items;
  final cp = pagination['currentPage'] ?? 1;
  final tp = pagination['totalPages'] ?? 1;

  return {
    'success': true,
    'threads': threads.map((t) => t.toJson()).toList(),
    'count': threads.length,
    'currentPage': cp,
    'totalPages': tp,
    'hasMore': cp < tp,
    'noMatch': threads.isEmpty,
    '_health': {
      'parser': info.parser,
      // 容器存在却解析不出帖子 = 结构可能变了（区别于"搜索确实无结果"）
      'missing': (threads.isEmpty && hasList)
          ? const ['列表容器存在但未解析出帖子']
          : const <String>[],
    },
  };
}

/// 从 HTML 兜底提取 searchid（分页链接里带 `searchid=数字`）。
///
/// 首选来源是响应重定向后的最终 URL（见 export.dart），此处仅兜底。
String? extractSearchId(String body) {
  final m = RegExp(r'searchid=(\d+)').firstMatch(body);
  return m?.group(1);
}
