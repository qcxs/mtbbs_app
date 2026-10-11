/// 「常用项自动前排」的排序：**第 1 项固定不动**，其余项按使用次数降序
/// （次数相同保持基准顺序，稳定排序）。
///
/// 为什么钉住第 1 项：它是**默认进入**的那个 Tab（导读的「最新发表」、消息页的
/// 「我的帖子」），位置一变用户感知最强 → 它的位置只由用户手动排序决定；
/// 本功能只负责让"翻 Tab 时常用的更靠前"。
///
/// 只在**次数不同**时才会换位——所以"手动排序后清空记录"能立刻生效
/// （全部为 0 → 完全按基准顺序），之后再由使用习惯慢慢调整。
List<String> orderByFrequency(List<String> base, Map<String, int> usage) {
  if (base.length < 2) return List.of(base);
  final rest = [for (var i = 1; i < base.length; i++) (i, base[i])];
  rest.sort((a, b) {
    final c = (usage[b.$2] ?? 0).compareTo(usage[a.$2] ?? 0);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [base.first, for (final e in rest) e.$2];
}
