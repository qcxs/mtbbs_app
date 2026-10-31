import 'package:mtbbs/config/notice_config.dart';
import 'package:mtbbs/core/app/default_config.dart';
import 'package:mtbbs/models/managed_item.dart';

/// 导读 Tab 默认 id（顺序即默认顺序）
const List<String> kDefaultGuideTabIds = [
  'newthread',
  'hot',
  'new',
  'digest',
  'sofa',
];

/// 导读 Tab 显示名
const Map<String, String> kSettingsTabLabels = {
  'newthread': '最新发表',
  'hot': '热门',
  'new': '最新回复',
  'digest': '精华',
  'sofa': '抢沙发',
  'my': '我的帖子',
};

/// 首页区块默认定义
const List<Map<String, dynamic>> kHomeSectionDefaults = [
  {'id': 'shortcuts', 'name': '快捷链接', 'visible': true, 'expanded': true},
  {'id': 'forums', 'name': '版块', 'visible': true, 'expanded': true},
  {'id': 'rank', 'name': '帖子排行', 'visible': true, 'expanded': true},
  {'id': 'rss', 'name': 'RSS 订阅', 'visible': false, 'expanded': false},
];

/// 合法首页区块 id
Set<String> get homeSectionIds => {
  for (final d in kHomeSectionDefaults) d['id'] as String,
};

/// 默认导读 Tab（全量含可见性）
List<ManagedItem> defaultGuideTabs() => [
  for (final id in kDefaultGuideTabIds)
    ManagedItem(id: id, name: kSettingsTabLabels[id] ?? id),
];

/// 默认首页区块
List<ManagedItem> defaultHomeSections() => [
  for (final d in kHomeSectionDefaults)
    ManagedItem(
      id: d['id'] as String,
      name: d['name'] as String,
      visible: d['visible'] as bool,
      data: {'expanded': d['expanded'] as bool},
    ),
];

/// 默认消息页 Tab
List<ManagedItem> defaultNoticeTabs() => [
  const ManagedItem(id: 'pm', name: '我的消息'),
  for (final g in noticeGroups) ManagedItem(id: g.id, name: g.label),
];

/// 合法消息页 Tab id
Set<String> get noticeTabIds => {'pm', for (final g in noticeGroups) g.id};

/// 默认常用语
List<ManagedItem> defaultQuickReplies() {
  final fromConfig = DefaultConfig.instance.quickReplies;
  if (fromConfig.isNotEmpty) return fromConfig;
  return const [
    ManagedItem(id: 'qr_thanks', name: '感谢分享'),
    ManagedItem(id: 'qr_hidden', name: '看看隐藏'),
    ManagedItem(id: 'qr_awesome', name: '论坛有你更精彩'),
  ];
}

/// 常用语显示文本长度上限
const int kQuickReplyMaxLength = 100;

/// 常用语插入内容长度上限
const int kQuickReplyInsertMaxLength = 500;

/// 「常用项自动前排」作用域 key
const String kTabUsageGuide = 'guide';
const String kTabUsageNotice = 'notice';
