/// 站内「提醒」（`home.php?mod=space&do=notice`）的分组与子类型。
///
/// **唯一数据源**：消息页的 Tab、分组内的子类型 chip、API 的
/// `view`/`type` 参数、以及未读徽标键都从这里派生。新增一类提醒 = 加一行。
///
/// 取值与 Discuz 源码严格对齐：
/// - 分组 id = Discuz `$_G['notice_structure']` 的 key
///   （`source/class/discuz/discuz_application.php`）
/// - 子类型 id = 同一结构里的 type 列表
/// - 中文名 = `source/language/lang_template.php` 的 `notice_{group}_{type}` /
///   `notice_{group}`（Discuz 按站点语言渲染，这里取简体中文）
library;

/// 提醒分组内的一个子类型（对应 Discuz 的 `type` 参数）
class NoticeType {
  /// Discuz 的 `type` 值，如 `post` / `wall`
  final String id;

  /// 展示名，如「帖子」「留言」
  final String label;

  const NoticeType(this.id, this.label);

  @override
  bool operator ==(Object other) =>
      other is NoticeType && other.id == id && other.label == label;

  @override
  int get hashCode => Object.hash(id, label);
}

/// 一个提醒分组（对应 Discuz 的一个 `view`）
class NoticeGroup {
  /// Discuz 的 `view` 值，如 `mypost` / `interactive`
  final String id;

  /// 展示名，如「我的帖子」
  final String label;

  /// 子类型；为空表示该视图不分类型（Discuz 按 category 取全量）
  final List<NoticeType> types;

  const NoticeGroup(this.id, this.label, {this.types = const []});

  /// 是否需要在页内再分子类型 Tab
  bool get hasTypes => types.isNotEmpty;
}

/// 消息页内的提醒分组（顺序即 Tab 顺序）。
///
/// 不含「我的消息」（私信，`do=pm`），它由 PmTab 单独承载。
const noticeGroups = <NoticeGroup>[
  // $_G['notice_structure']['mypost']
  NoticeGroup(
    'mypost',
    '我的帖子',
    types: [
      NoticeType('post', '帖子'),
      NoticeType('rate', '评分'),
      NoticeType('pcomment', '点评'),
      NoticeType('activity', '活动'),
      NoticeType('reward', '悬赏'),
      NoticeType('goods', '商品'),
      NoticeType('at', '提到我的'),
    ],
  ),
  // $_G['notice_structure']['interactive']
  NoticeGroup(
    'interactive',
    '坛友互动',
    types: [
      NoticeType('poke', '打招呼'),
      NoticeType('friend', '好友'),
      NoticeType('wall', '留言'),
      NoticeType('comment', '评论'),
      NoticeType('click', '挺你'),
      NoticeType('sharenotice', '分享'),
    ],
  ),
  // $_G['notice_structure']['system']（不分 type，按 category 取全量）
  NoticeGroup('system', '系统提醒'),
  // $_G['notice_structure']['manage']
  NoticeGroup('manage', '管理工作'),
  // $_G['notice_structure']['app']：类型由站点插件自行扩展，故不分子类型
  NoticeGroup('app', '应用提醒'),
];

/// 按 id 取分组（找不到返回 null）
NoticeGroup? noticeGroupOf(String id) {
  for (final g in noticeGroups) {
    if (g.id == id) return g;
  }
  return null;
}

/// 所有分组的 id
Set<String> get noticeGroupIds => {for (final g in noticeGroups) g.id};

/// 未读徽标的样式（仿 PiliPlus 的 DynamicBadgeMode）
enum NoticeBadgeMode {
  hidden('隐藏'),
  point('红点'),
  number('数字');

  final String desc;
  const NoticeBadgeMode(this.desc);
}
