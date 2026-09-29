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
