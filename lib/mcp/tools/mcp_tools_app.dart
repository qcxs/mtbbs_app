import 'package:mtbbs/mcp/mcp_types.dart';
import 'package:mtbbs/mcp/tools/mcp_payloads.dart';
import 'package:mtbbs/mcp/tools/mcp_tool_definition.dart';

/// App 信息组工具（`McpToolGroup.appInfo`）
///
/// 只回版本、构建元数据、仓库链接、站点与登录状态，**不含任何凭据**
/// （token / cookie / formhash）。
/// [allowCrossSite] / [allowAccountSwitch] 仅用于让 `help` 如实告知当前权限。
List<McpToolDefinition> appTools(
  McpAccountInfoProvider accountInfo, {
  bool allowCrossSite = true,
  bool allowAccountSwitch = false,
}) => [
  McpToolDefinition(
    name: 'get_app_info',
    group: McpToolGroup.appInfo,
    description:
        '获取 App 版本与构建信息（版本名/构建号/提交/构建时间/渠道/Beta）、'
        '仓库与发布链接、当前论坛站点与登录状态（不含任何凭据）。'
        '用于判断版本、排查构建差异、告知用户去哪看更新，以及确认能否读取需登录的内容。',
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
    run: (args) async => _help(
      allowCrossSite: allowCrossSite,
      allowAccountSwitch: allowAccountSwitch,
    ),
  ),
];

/// 使用指南内容（`help` 工具的返回）。
///
/// 刻意做成结构化的 Map 而不是一大段文本：AI 更容易按 `scenarios` 直接选路，
/// 也便于后续增删场景而不影响其它字段。
Map<String, dynamic> _help({
  required bool allowCrossSite,
  required bool allowAccountSwitch,
}) => {
  'what':
      '本服务是 Discuz 论坛客户端 MTBBS 暴露的**只读数据接口**，'
      '让 AI 读取论坛内容（帖子、用户、版块、排行、本地草稿等）；'
      '另提供两个本地工具：codec_text 编解码、open_app_page 打开 App 内容页。',
  'principles': [
    '没有任何发帖/回复/修改/收藏类操作；open_app_page 只切换 App 当前页面，不写入数据。',
    '编解码与导航是本地能力，不发 HTTP，不受错峰队列影响。',
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
    {
      'task': '读帖子但时效性要求不高（尽量少发请求）',
      'steps': [
        'get_thread_detail(tid, source=auto) 默认即缓存优先：有未过期的本地缓存就不发 HTTP',
        '返回里 source=cache 时看 cache.stale / cache.cachedPages / cacheNote 判断是否够用',
        '需要最新回复时再用 get_thread_detail(tid, source=network) 强制联网',
      ],
      'note':
          'source=cache 只读缓存、未命中返回 cacheMiss=true 且不发请求；'
          '缓存通常只含访问过的页码，深页缺失时会回退联网（auto）或明确返回缺失页。',
    },
    {
      'task': '还原帖子里的编码内容（链接 / Base64 / 十六进制）',
      'steps': [
        'codec_text(op=base64, direction=decode, text=...) 解码 Base64',
        'codec_text(op=url, direction=decode, text=...) 还原 URL 编码',
        'codec_text(op=hex, direction=decode, text=...) 还原十六进制；'
            'op=md5/sha1/sha256 可直接算摘要',
      ],
    },
    {
      'task': '在 App 里打开某个页面',
      'steps': [
        'open_app_page(target=thread, id=tid, page=N) 打开帖子',
        'open_app_page(target=user, id=uid) / target=forum, id=fid 打开用户或版块',
        'open_app_page(target=search, keyword=...) 打开搜索结果页',
      ],
      'note':
          '仅在用户明确要求打开/跳转时调用；只开放内容页白名单'
          '（帖子/用户/版块/搜索/导读/首页），设置、编辑器、内置浏览器与私信页不可用。',
    },
    if (allowCrossSite || allowAccountSwitch)
      {
        'task': '跨站点 / 换账号视角读取（需用户已在设置中开启权限）',
        'steps': [
          if (allowCrossSite)
            'list_sites 先看已配置站点（isInUse 标出本次会用的站点）',
          if (allowCrossSite)
            '任意读取工具追加 site=域名或站点名，如 list_guide_threads(site=52pojie)',
          if (allowAccountSwitch)
            '追加 account=账号名，以该站点其它已登录账号的视角读取（只读）',
          if (allowCrossSite)
            'open_app_page(target=thread, id=tid, site=其它站点) 可跨站打开帖子 / 用户 / 搜索页',
        ],
        'note':
            'site 与 account 只对本次调用生效，不会改变 App 当前站点或登录态；'
            '未填时沿用当前站点与当前账号。缓存读帖也按目标站点 + 账号隔离。',
      },
    {
      'task': '浏览圈子与留言板',
      'steps': [
        'list_groups 取推荐圈子、圈子分类与积分排行',
        'list_group_forums(gid) 看某分类下的圈子列表',
        'list_forum_threads(fid=gid) 读某个圈子的帖子（圈子讨论区就是 fid=gid 的版块）',
        'list_wall_messages(uid) 看某用户留言板（省略 uid = 当前账号）',
      ],
    },
  ],
  'conventions': [
    'uid 省略 = 当前登录账号；显式传入 = 指定该用户。',
    '分页统一用 page（从 1 开始），返回里有 currentPage / totalPages / hasMore。'
        '例外：search_forum_threads 翻页要回传 search_id（仅传 page 不生效）。',
    'get_thread_detail 默认只回前 10 层、正文精简；用 max_posts 调层数、'
        'full_bbcode=true 取逐字原文。单层正文超长会分片：该层带 bbcodeNextOffset，'
        '用它作为 bbcode_offset 再次调用即可续读同一层（full_bbcode 要保持一致）。',
    'get_thread_detail 的 source 控制数据来源：auto（默认，缓存优先）/ '
        'network（强制最新）/ cache（只读缓存）。返回的 source 字段标明实际来源。',
    'codec_text 只做本地计算；输入上限 20 万字符，超长请先截取。',
    'open_app_page 的 id 必须是数字；App 需在前台，后台调用不会把界面带到前台。',
    if (allowCrossSite)
      'site 可填域名或站点名（先用 list_sites 确认）；只对已配置站点生效，'
          '返回里的 host / source 会标明实际站点。',
    if (allowAccountSwitch)
      'account 必须是该站点已登录的账号名；它只换读取视角，不会修改 App 当前登录态。',
  ],
  'permissions': {
    'crossSite': allowCrossSite,
    'accountSwitch': allowAccountSwitch,
    'note': switch ((allowCrossSite, allowAccountSwitch)) {
      (true, true) => '跨站点与切换账号视角均已开启；未填 site / account 时沿用当前站点与当前账号。',
      (true, false) =>
        '跨站点已开启（公开信息默认开启）；切换账号视角未开启，'
            '不要传 account，如任务确实需要请提示用户到「设置 → MCP 服务 → 跨站点与身份」开启。',
      (false, true) =>
        '切换账号视角已开启；跨站点访问未开启，不要传 site，'
            '如任务确实需要请提示用户到「设置 → MCP 服务 → 跨站点与身份」开启。',
      (false, false) =>
        '跨站点与切换账号视角均未开启；如任务确实需要，请提示用户到'
            '「设置 → MCP 服务 → 跨站点与身份」手动开启，不要反复重试。',
    },
  },
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
