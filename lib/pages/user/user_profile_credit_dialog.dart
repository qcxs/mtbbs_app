part of 'user_profile_page.dart';

/// 用户主页 — 积分分析弹窗。
///
/// 通过 `part of` 与 user_profile_page.dart 共享库内私有成员。
extension on _UserProfilePageState {
  // ==================== 积分分析弹窗 ====================

  /// 显示积分分析弹窗（饼图 + 积分占比 + 精华帖数）
  void _showCreditDialog() {
    final settings = context.read<SettingsProvider>();
    if (settings.creditFormula.isEmpty) {
      showToast('请登录后在设置页面中刷新积分公式后使用');
      return;
    }

    final p = _profile!;
    final computed = _computeCreditData(p);
    if (computed == null) return;

    final segments = computed.$1;
    final totalCalc = computed.$2;
    final elitePosts = computed.$3;
    final formulaStr = computed.$4;
    final diff = computed.$5;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.pie_chart_outline,
                      size: 18,
                      color: _cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      '积分分析',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '公式: $formulaStr',
                  style: TextStyle(
                    fontSize: 10,
                    color: _cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (diff < 10) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        '估算精华帖: ',
                        style: TextStyle(
                          fontSize: 14,
                          color: _cs.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '$elitePosts 篇',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '(可能不准确)',
                        style: TextStyle(
                          fontSize: 12,
                          color: _cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                // 饼图 + 图例
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    PieChart(segments: segments, size: 130, strokeWidth: 30),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: segments.map((s) {
                          final pct = (s.value / totalCalc * 100);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: s.color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    s.label,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${pct.toStringAsFixed(1)}%',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 计算积分分析数据，返回 (segments, totalCalc, elitePosts, formulaStr, diff)
  (List<PieChartSegment>, double, int, String, double)? _computeCreditData(
    Map<String, dynamic> p,
  ) {
    final points = p['points'] as Map<String, dynamic>? ?? {};
    final stats = p['stats'] as Map<String, dynamic>? ?? {};
    final activity = p['activity'] as Map<String, dynamic>? ?? {};

    final credits = _n(points['credits']);
    final goldCoins = _n(points['goldCoins']);
    final threads = _n(stats['threads']);
    final replies = _n(stats['replies']);
    final totalPosts = threads + replies;
    final reputation = _n(points['reputation']);
    final credit = _n(points['credit']);
    final friends = _n(stats['friends']);
    final onlineTime = _extractHours(activity['onlineTime'] as String?);

    if (credits <= 0) return null;

    final settings = context.read<SettingsProvider>();
    final formulaStr = settings.creditFormula;

    final termGold = goldCoins * 0.2;
    final termThreads = threads * 3;
    final termPosts = totalPosts * 1.5;
    final termReputation = reputation * 5;
    final termCredit = (credit - 100) * 5;
    final termFriends = (1 - 1 / (friends / 500 + 1)) * 5000;
    final termOnline = (1 - 1 / (onlineTime / 5000 + 1)) * 20000;

    final knownSum =
        termGold +
        termThreads +
        termPosts +
        termReputation +
        termCredit +
        termFriends +
        termOnline;

    final eliteContribution = credits - knownSum;
    final elitePosts = (eliteContribution / 30).round().clamp(0, 999);
    final termElite = elitePosts * 30.0;

    final totalCalc = knownSum + termElite;
    final diff = (totalCalc - credits).abs();

    final segments = <PieChartSegment>[];
    void addSeg(String label, double value, Color color) {
      if (value > 0.5) {
        segments.add(PieChartSegment(label: label, value: value, color: color));
      }
    }

    addSeg('金币', termGold, const Color(0xFFFFC107));
    addSeg('主题', termThreads, const Color(0xFF3F51B5));
    addSeg('发帖', termPosts, const Color(0xFF00BCD4));
    if (elitePosts > 0) addSeg('精华', termElite, const Color(0xFFFF9800));
    addSeg('好评', termReputation, const Color(0xFF4CAF50));
    addSeg('信誉', termCredit < 0 ? 0 : termCredit, const Color(0xFF2196F3));
    addSeg('好友', termFriends, const Color(0xFFE91E63));
    addSeg('在线', termOnline, const Color(0xFF9C27B0));

    return (segments, totalCalc, elitePosts, formulaStr, diff);
  }
}
