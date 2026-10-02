import 'package:mtbbs/mcp/mcp_types.dart';
import 'package:mtbbs/mcp/tools/mcp_payloads.dart';
import 'package:mtbbs/mcp/tools/mcp_tool_definition.dart';

/// App 信息组工具（`McpToolGroup.appInfo`）
///
/// 只回版本、站点与登录状态，**不含任何凭据**（token / cookie / formhash）。
List<McpToolDefinition> appTools(McpAccountInfoProvider accountInfo) => [
  McpToolDefinition(
    name: 'get_app_info',
    group: McpToolGroup.appInfo,
    description: '获取 App 版本、当前论坛站点与登录状态（不含任何凭据）。用于判断能否读取需登录的内容。',
    properties: const {},
    network: false, // 纯本地
    run: (args) async => McpPayloads.appInfo(accountInfo),
  ),
  McpToolDefinition(
    name: 'list_sites',
    group: McpToolGroup.appInfo,
    description: '列出 App 中已配置的论坛站点（名称与域名），并标出当前站点。',
    properties: const {},
    network: false, // 纯本地
    run: (args) async => {'sites': McpPayloads.sites()},
  ),
  McpToolDefinition(
    name: 'help',
    group: McpToolGroup.appInfo,
    description:
        '**使用指南：第一次使用本服务时请先调用它**。说明本服务能做什么、'
        '几类典型任务该按什么顺序组合工具、参数约定与注意事项。',
    properties: const {},
    network: false, // 纯文本，不发请求
    run: (args) async => _help(),
  ),
];

/// 使用指南内容（`help` 工具的返回）。
///
/// 刻意做成结构化的 Map 而不是一大段文本：AI 更容易按 `scenarios` 直接选路，
/// 也便于后续增删场景而不影响其它字段。
Map<String, dynamic> _help() => {
  'what':
      '本服务是 Discuz 论坛客户端 MTBBS 暴露的**只读**数据接口，'
      '让 AI 读取论坛内容（帖子、用户、版块、排行、本地草稿等）。',
  'principles': [
    '全部只读：没有任何发帖/回复/修改/收藏类操作。',
    '数据走用户当前登录态，可见范围与 App 内完全一致'
        '（比如回复可见的帖子，是否能看到内容取决于该账号是否已回复）。',
    '会发请求的工具自动过全局错峰队列：连续大量调用会逐个放行，变慢属正常的防封保护。',
  ],
  'scenarios': [
    {
      'task': '总结最近帖子',
      'steps': [
        'list_guide_threads(view=newthread) 取最新帖列表（view=hot 看热门、digest 看精华）',
        '挑出感兴趣的 tid，用 get_thread_detail(tid) 读正文',
      ],
    },
    {
      'task': '总结当前账号',
      'steps': [
        'get_app_info 取站点与登录状态',
        'get_user_profile() 取自己的资料（省略 uid 即当前账号）',
        'list_user_threads() 看我发过的主题（type=reply 看我的回复）',
        'list_my_favorites() / get_browse_history() 看收藏与浏览倾向',
      ],
    },
    {
      'task': '总结某个用户（例如 uid=100）',
      'steps': [
        'get_user_profile(uid=100) 取资料：昵称、用户组、签名、发帖数',
        'list_user_threads(uid=100) 看他发过什么（type=reply 看他的回复）',
        'list_user_friends(uid=100) / list_user_follows(uid=100) 看社交圈',
        '再挑几篇 get_thread_detail 深入读，综合判断"他是什么样的人"',
      ],
      'note':
          '能否看他人列表取决于站点隐私设置；被限制时返回里带 '
          'privacyBlocked 或 loginRequired，而不是空列表。',
    },
    {
      'task': '查看编辑器里正在写/写过的文章',
      'steps': [
        'list_editor_sessions 列出草稿会话（发帖/回复/评论）',
        'get_editor_draft(session_key) 取正文：默认已剔除纯样式标签、便于阅读；'
            '需要逐字原文（含样式）时传 full_bbcode=true',
      ],
      'note': '草稿由 App 自动保存，最近一次快照可能滞后数十秒。',
    },
    {
      'task': '搜索论坛内容（关键词）',
      'steps': [
        'search_forum_threads(keyword=关键词) 取搜索结果列表与 searchId',
        '需要更多结果时：search_forum_threads(search_id=上次的 searchId, page=2)',
        '挑出 tid，用 get_thread_detail(tid) 读正文',
      ],
      'note':
          '站点对新搜索有频率限制（短时间内重复搜同一/不同词都可能被拒），'
          '翻页务必回传 search_id 以避免新建搜索；无结果返回 noMatch=true，'
          '需登录返回 loginRequired=true。',
    },
  ],
  'conventions': [
    'uid 省略 = 当前登录账号；显式传入 = 指定该用户。',
    '分页统一用 page（从 1 开始），返回里有 currentPage / totalPages / hasMore。'
        '例外：search_forum_threads 翻页要回传 search_id（仅传 page 不生效）。',
    'get_thread_detail 默认只回前 10 层、正文精简；用 max_posts 调层数、'
        'full_bbcode=true 取逐字原文。',
  ],
  'groups': [
    for (final g in McpToolGroup.values)
      {
        'id': g.id,
        'label': g.label,
        'description': g.description,
        'defaultEnabled': g.defaultEnabled,
      },
  ],
  'caveat':
      '某个能力返回"已在 App 中关闭"时，说明用户在设置里关掉了该能力分组，'
      '请提示用户在「设置 → MCP 服务 → 能力开关」中开启，不要反复重试。',
};
