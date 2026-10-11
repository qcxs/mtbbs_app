import 'package:flutter/foundation.dart';
import 'package:mtbbs/api/home/notice_unread/export.dart' as unread_api;
import 'package:mtbbs/core/app/notice_nav_store.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/services/api_service.dart';

/// 未读提醒的探测与徽标状态（单例，Provider 注册）。
///
/// 设计取自经过大量用户验证的 PiliPlus（B 站客户端）：
/// - **不用定时器**，只在事件点检查：冷启动 / 回前台 / 返回主壳 / 切到消息 Tab /
///   手动下拉刷新
/// - 每次先判节流 —— 无论触发多频繁，**最多 [minInterval] 一次**（省电、省流量）
/// - 只在登录 + 开关打开 + 有关注分组时才请求；不满足时由调用方 [clear]
/// - 无变化不通知（避免无谓重建）
///
/// 计数来源见 `lib/api/home/notice_unread/http.dart`（非破坏性，绝不打开通知页）。
class NoticeBadgeController extends ChangeNotifier {
  NoticeBadgeController._();

  static final NoticeBadgeController instance = NoticeBadgeController._();

  /// 节流周期。PiliPlus 同为 5 分钟；Discuz 这边探测是整页 HTML（还可能要过 WAF），
  /// 故**固定不开放给用户配**，避免有人设成 1 分钟把站点请求打爆。
  static const Duration minInterval = Duration(minutes: 5);

  Map<String, int> _byGroup = const {};
  bool _hasNewPm = false;
  int _lastCheckAt = 0;
  bool _inFlight = false;

  /// 各分组未读数（key = NoticeGroup.id）——最近一次**探测/页面**给的原始值。
  /// 上层请用 [countOf]（数据驱动，会优先按子类型求和）。
  Map<String, int> get byGroup => _byGroup;

  /// 某分组的未读数（**数据驱动**）：
  /// - 已知该视图的子类型计数 → 各子类型之和（子类型一变化，分组立刻跟着变，
  ///   不必等下一次探测；Discuz 的 `category_num[view]` 本就是子类型之和）
  /// - 否则 → 最近一次探测得到的视图级计数
  int countOf(String view) =>
      NoticeNavStore.instance.subtypeSum(view) ?? (_byGroup[view] ?? 0);

  /// 是否有未读私信（Discuz 的 header 只给"有/无"，不给条数）
  bool get hasNewPm => _hasNewPm;

  /// 用户勾选的分组未读之和
  int countFor(Set<String> groups) =>
      groups.fold(0, (sum, id) => sum + countOf(id));

  /// 无子类型的视图（系统提醒/管理工作/应用提醒）：页面一打开就把本次拉到的
  /// 未读全置已读了（未读必在第 1 页），而页面渲染的是**读前**的计数
  /// （Discuz 每个请求开头才算一次 newprompt），所以这里乐观清零。
  void markViewRead(String view) {
    if ((_byGroup[view] ?? 0) == 0) return;
    _byGroup = {..._byGroup, view: 0};
    notifyListeners();
  }

  /// 是否有任何未读（分组或私信）
  bool get hasAny => _byGroup.keys.any((k) => countOf(k) > 0) || _hasNewPm;

  /// 检查未读。受 [minInterval] 节流；[force] 用于手动刷新。
  Future<void> check({bool force = false}) async {
    if (_inFlight) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _lastCheckAt < minInterval.inMilliseconds) return;
    _lastCheckAt = now; // 先占位，避免并发重复请求
    _inFlight = true;
    try {
      final r = await unread_api.getNoticeUnread(ApiService().dio);
      if (r['success'] != true) return;
      final byGroup = <String, int>{};
      (r['byGroup'] as Map?)?.forEach((k, v) {
        byGroup['$k'] = (v as num?)?.toInt() ?? 0;
      });
      final hasNewPm = r['hasNewPm'] == true;
      // 探测是"探测那一刻"的权威值。若与"子类型之和"对不上，说明期间来了新消息，
      // 子类型数据已过期 → 丢弃它，让 [countOf] 回到探测值兜底。
      _dropStaleSubtypeCounts(byGroup);
      if (mapEquals(_byGroup, byGroup) && _hasNewPm == hasNewPm) return;
      _byGroup = byGroup;
      _hasNewPm = hasNewPm;
      notifyListeners();
    } catch (e) {
      AppLogger.w('PAGE', 'notice unread check failed: $e');
    } finally {
      _inFlight = false;
    }
  }

  /// 丢弃"已过期"的子类型计数：探测（权威）给的组计数与子类型之和不一致，
  /// 说明这期间来了新消息（未读只增不减地变化过），子类型数据不再可信。
  void _dropStaleSubtypeCounts(Map<String, int> probe) {
    final nav = NoticeNavStore.instance;
    for (final v in nav.views) {
      final sum = nav.subtypeSum(v.id);
      if (sum == null) continue;
      if (sum != (probe[v.id] ?? 0)) nav.dropSubtypeCounts(v.id);
    }
  }

  /// 退出登录 / 关掉开关时清空徽标
  void clear() {
    if (_byGroup.isEmpty && !_hasNewPm) return;
    _byGroup = const {};
    _hasNewPm = false;
    notifyListeners();
  }

  /// 用**提醒页面自带的计数**（侧栏每个视图的 `(N)`）覆盖分组未读。
  ///
  /// 这份计数是服务端在**本页置已读之后**渲染的（`space_notice.php` 先 `ignore()`
  /// 再输出模板），因此比"本地猜"权威。也正因如此，不能简单地"整组清零"：
  /// 打开「帖子」子类型时未读可能全在「点评」上，服务端什么都没置已读，
  /// 页面计数仍是 1 —— 用页面计数覆盖后，徽标与真实状态一致，
  /// 不会出现"先清空、下次探测又冒出来"。
  void applyViewCounts(Map<String, int> counts) {
    // 本次页面已经给出权威计数，算作一次检查（与 PiliPlus 重置 lastCheckUnreadAt 同理）
    _lastCheckAt = DateTime.now().millisecondsSinceEpoch;
    if (mapEquals(_byGroup, counts)) return;
    _byGroup = Map.unmodifiable(counts);
    notifyListeners();
  }
}
