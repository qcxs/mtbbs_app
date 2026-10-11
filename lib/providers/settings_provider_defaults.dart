part of 'settings_provider.dart';

/// 导读 Tab 默认 id 列表（顺序即默认顺序）
const _defaultTabIds = ['newthread', 'hot', 'new', 'digest', 'sofa'];

/// 首页区块默认定义：顺序、显示名、是否显示、是否默认展开。
///
/// RSS 默认隐藏 —— 内容与导读 Tab 重合，用户可在
/// 「设置 → 外观 → 首页区块」里重新开启。
const List<Map<String, dynamic>> _homeSectionDefaults = [
  {'id': 'shortcuts', 'name': '快捷链接', 'visible': true, 'expanded': true},
  {'id': 'forums', 'name': '版块', 'visible': true, 'expanded': true},
  {'id': 'rank', 'name': '帖子排行', 'visible': true, 'expanded': true},
  {'id': 'rss', 'name': 'RSS 订阅', 'visible': false, 'expanded': false},
];

/// 合法首页区块 id，用于过滤损坏的持久化数据
final Set<String> _homeSectionIds = {
  for (final d in _homeSectionDefaults) d['id'] as String,
};

/// 帖子迷你编辑器「常用语」显示文本长度上限（字符数）
const int kQuickReplyMaxLength = 100;

/// 帖子迷你编辑器「常用语」插入内容长度上限（可含 BBCode，故更宽松）
const int kQuickReplyInsertMaxLength = 500;

/// 「常用项自动前排」的两个作用域（作 [SettingsProvider.tabUsage] 的 key）
const String kTabUsageGuide = 'guide';
const String kTabUsageNotice = 'notice';

/// 消息页 Tab 默认定义（顺序即默认顺序）。
/// 「我的消息」= 私信；其余 id 与 `notice_config` 的 [noticeGroups] 一致。
List<ManagedItem> defaultNoticeTabs() => [
  const ManagedItem(id: 'pm', name: '我的消息'),
  for (final g in noticeGroups) ManagedItem(id: g.id, name: g.label),
];

/// 合法消息页 Tab id（用于过滤损坏的持久化数据）
final Set<String> _noticeTabIds = {
  'pm',
  for (final g in noticeGroups) g.id,
};

/// 帖子迷你编辑器「常用语」默认项
/// 优先从 [DefaultConfig]（`assets/config/quick_replies.json`）加载，失败用内嵌兜底。
List<ManagedItem> defaultQuickReplies() {
  final fromConfig = DefaultConfig.instance.quickReplies;
  if (fromConfig.isNotEmpty) return fromConfig;
  return const [
    ManagedItem(id: 'qr_thanks', name: '感谢分享'),
    ManagedItem(id: 'qr_hidden', name: '看看隐藏'),
    ManagedItem(id: 'qr_awesome', name: '论坛有你更精彩'),
  ];
}
