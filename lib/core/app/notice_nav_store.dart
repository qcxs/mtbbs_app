import 'package:flutter/foundation.dart';
import 'package:mtbbs/config/notice_config.dart';
import 'package:mtbbs/core/utils/logger.dart';

/// 站点**实际**有哪些提醒视图 / 子类型（由提醒页面自带的导航同步而来）。
///
/// 为什么不写死：Discuz 会按权限与配置增删视图/子类型（源码依据见
/// `api/home/notice/parse.dart` 的 `_parseNav`）——
/// - 非管理员的 `manage` 被 `unset`，`view=manage` 会被服务端降级成 `all`
/// - 站点没有的子类型，带 `type=X` 请求会被**静默改成默认子类型**（拿回别人的数据）
///
/// 因此消息页的 Tab 与页内子类型 chip 都要按这份导航裁剪；未同步前调用方
/// 回退到 [noticeGroups]（保证首屏可用）。
class NoticeNavStore extends ChangeNotifier {
  NoticeNavStore._();

  static final NoticeNavStore instance = NoticeNavStore._();

  List<NoticeType> _views = const [];
  Map<String, List<NoticeType>> _subtypes = const {};

  /// 组级未读（页面侧栏的 `(N)`，服务端置已读之后的权威值）
  Map<String, int> _viewCounts = const {};

  /// 子类型未读（页面子栏的 `(N)`），键为 `view/type`
  Map<String, int> _subtypeCounts = const {};

  /// 各视图最近一次实际打开的子类型（不传 type 时即"第一个有未读的"）。
  ///
  /// **必须按 view 隔离**：`system` / `manage` / `app` 没有子类型栏，
  /// 若共用一个字段，它们会继承上一个有子类型视图（如 `mypost/post`）的值，
  /// 导致 `NoticeTab._applyNav` 误判"系统提醒有子类型 wall/post"，
  /// 从而只调 `markSubtypeRead` 而不清零组级徽标（见 docs/07 #97）。
  Map<String, String> _activeSubtypeByView = const {};

  /// 站点返回的视图（空 = 尚未同步 → 调用方回退到配置）
  List<NoticeType> get views => _views;

  /// 是否已同步过（至少拉到一次站点导航）
  bool get synced => _views.isNotEmpty;

  /// 组级未读（来自页面侧栏，权威）
  Map<String, int> get viewCounts => _viewCounts;

  /// 指定视图最近一次打开的子类型（无子类型的视图恒为空串）
  String activeSubtypeFor(String view) => _activeSubtypeByView[view] ?? '';

  /// 指定子类型的未读（来自页面子栏）
  int subtypeCount(String view, String type) =>
      _subtypeCounts['$view/$type'] ?? 0;

  /// 该视图按子类型求和得到的未读；`null` = 尚无子类型数据（调用方回退到探测值）。
  ///
  /// 这是**数据驱动**的落点：分组未读 = 各子类型之和（Discuz 的
  /// `category_num[view]` 本就是该视图各 `newprompt_num[type]` 的和），
  /// 所以子类型一变化，分组数立刻跟着变，不需要再等一次探测。
  int? subtypeSum(String view) {
    final types = _subtypes[view];
    if (types == null || types.isEmpty) return null;
    var sum = 0;
    for (final t in types) {
      sum += _subtypeCounts['$view/${t.id}'] ?? 0;
    }
    return sum;
  }

  /// "子类型数据被判过期并丢弃"的次数。
  ///
  /// 消息页据此**重建当前分组页**（重新拉取）：丢弃后子类型已不可信，
  /// 与其显示不一致的中间状态，不如直接按站点最新数据重构。
  int get dropRevision => _dropRevision;
  int _dropRevision = 0;

  /// 丢弃某视图的子类型数据（判为过期时用，之后回落到探测值）。
  ///
  /// 触发场景：探测（header，权威）拿回来的组计数与"子类型之和"对不上，
  /// 说明期间来了新消息，子类型数据已过期。
  void dropSubtypeCounts(String view) {
    final types = _subtypes[view];
    if (types == null || types.isEmpty) return;
    final next = Map<String, int>.from(_subtypeCounts)
      ..removeWhere((k, _) => k.startsWith('$view/'));
    _subtypes = Map<String, List<NoticeType>>.from(_subtypes)..remove(view);
    _subtypeCounts = next;
    _dropRevision++;
    notifyListeners();
  }

  /// 指定视图的子类型；`null` = 尚未同步（调用方回退到配置）
  List<NoticeType>? subtypesOf(String view) => _subtypes[view];

  /// 某个子类型刚被用户打开阅读（服务端已把**本次拉到的**该子类型条目置为已读）
  /// → 立刻清零它的未读。
  ///
  /// 为什么必须乐观清零：子类型计数只可能来自"打开过的提醒页"，而探测走的
  /// header **只有 view 级计数** —— 读完子类型后若不清，这个数字没有任何时机
  /// 会被更新，会一直挂着上一次页面上的旧值。
  /// （服务端渲染的是读前还是读后的值都不影响结论：**这次拉取本身**就把该子类型
  /// 置为已读了，所以清零一定正确；本来就为 0 时是空操作。）
  void markSubtypeRead(String view, String type) {
    final key = '$view/$type';
    if ((_subtypeCounts[key] ?? 0) == 0) return;
    _subtypeCounts = {..._subtypeCounts, key: 0};
    notifyListeners();
  }

  /// 用一次提醒页返回结果里的 `nav` 同步。
  ///
  /// [requestedView] 是本次请求的 view。若它不在返回的视图列表里（被 unset /
  /// 权限不足 / 服务端降级成 all），就不写进去 —— 消息页的对应 Tab 自然消失。
  void syncFromPage(
    Map<String, dynamic>? nav, {
    required String requestedView,
  }) {
    if (nav == null) return;

    final views = <NoticeType>[];
    final viewCounts = <String, int>{};
    for (final v in (nav['views'] as List?) ?? const []) {
      if (v is! Map) continue;
      final id = v['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      // 标签优先用站点渲染的（站点可能自定义/本地化），缺失再回退 config
      final siteLabel = v['label']?.toString() ?? '';
      views.add(
        NoticeType(
          id,
          siteLabel.isNotEmpty ? siteLabel : (noticeGroupOf(id)?.label ?? id),
        ),
      );
      viewCounts[id] = (v['count'] as num?)?.toInt() ?? 0;
    }
    // 侧栏解析不到（模板差异）→ 保持现状，别把 Tab 清空
    if (views.isEmpty) {
      AppLogger.w('PARSE', 'notice nav 解析为空，保持现状（requested=$requestedView）');
      return;
    }

    final exists =
        requestedView == 'all' || views.any((v) => v.id == requestedView);
    if (!exists) {
      AppLogger.i(
        'PARSE',
        'notice view 站点不存在 → 移除 Tab: $requestedView '
            '（站点实际=${views.map((e) => e.id).join('/')}）',
      );
    }

    // 子类型：只有站点真的渲染了子类型栏、且该视图存在时才覆盖
    final nextSubtypes = Map<String, List<NoticeType>>.from(_subtypes);
    final nextSubCounts = Map<String, int>.from(_subtypeCounts);
    final nextActive = Map<String, String>.from(_activeSubtypeByView);
    if (exists && nav['hasSubBar'] == true) {
      final subs = <NoticeType>[];
      for (final s in (nav['subtypes'] as List?) ?? const []) {
        if (s is! Map) continue;
        final id = s['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        subs.add(NoticeType(id, s['label']?.toString() ?? id));
        nextSubCounts['$requestedView/$id'] =
            (s['count'] as num?)?.toInt() ?? 0;
      }
      nextSubtypes[requestedView] = subs;
      // 无子类型的视图（system/manage/app）也要写入空串：按 view 覆盖，
      // 不能因为"本次为空"就保留该视图上一次的值。
      nextActive[requestedView] = nav['activeSubtype']?.toString() ?? '';
    }

    _views = views;
    _subtypes = nextSubtypes;
    _viewCounts = viewCounts;
    _subtypeCounts = nextSubCounts;
    _activeSubtypeByView = nextActive;
    notifyListeners();
  }

  /// 退出登录 / 切换站点时清空（回到配置兜底状态）
  void clear() {
    if (_views.isEmpty && _subtypes.isEmpty) return;
    _views = const [];
    _subtypes = const {};
    _viewCounts = const {};
    _subtypeCounts = const {};
    _activeSubtypeByView = const {};
    notifyListeners();
  }
}
