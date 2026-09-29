/// 预览里的「选中高亮」—— 用 `[backcolor]` 把选区包起来。
///
/// 为什么用 BBCode 包裹，而不是在渲染层画高亮：
/// 1. **不影响排版**：包一层标签不会挪动任何行位置（对比早期试过的零宽锚点注入，
///    实测会把行位置挪十几像素、预览就不再等于真实帖子）
/// 2. **天然字符级**：不需要建立"字符偏移 → 渲染位置"的映射
/// 3. 复用现成管线，零新增渲染逻辑
///
/// 代价与约束：
/// - 只能**整段包裹**，所以边界必须吸附到标签外沿，否则会把 `[b]` 切成 `[b` + `]`
/// - 选区若横跨"外层开标签在选区外、闭标签在选区内"这类不平衡情形，
///   包裹后标签会错配 —— 预览里会渲染得怪一点，但不会崩，也不影响提交内容
///   （提交走 `_contentCtl.text`，本函数只作用于预览字符串）
library;

/// 把 [source] 的 `[start, end)` 区间用 `[backcolor=色值]` 包起来。
///
/// [start] / [end] 会先吸附到标签外沿；吸附后区间为空（或原本就空）则原样返回。
String bbcodeHighlightSelection(
  String source,
  int start,
  int end,
  String color,
) {
  if (source.isEmpty) return source;
  var s = start < 0 ? 0 : (start > source.length ? source.length : start);
  var e = end < 0 ? 0 : (end > source.length ? source.length : end);
  if (s > e) {
    final t = s;
    s = e;
    e = t;
  }
  s = _snapForward(source, s);
  e = _snapBackward(source, e);
  if (s >= e) return source;
  return '${source.substring(0, s)}'
      '[backcolor=$color]${source.substring(s, e)}[/backcolor]'
      '${source.substring(e)}';
}

/// 把位置 [i] 从"标签内部"推到标签之后。
///
/// 判断方式：找 [i] 之前最近的 `[`；若它对应的 `]` 在 [i] 之后（或不存在闭合），
/// 说明 [i] 落在这个标签内部。
int _snapForward(String source, int i) {
  if (i <= 0) return i;
  final open = source.lastIndexOf('[', i - 1);
  if (open < 0) return i;
  final close = source.indexOf(']', open);
  if (close < 0) return i; // 未闭合的 '[' → 视为普通字符，不动
  return close >= i ? close + 1 : i;
}

/// 把位置 [i] 从"标签内部"拉回标签之前
int _snapBackward(String source, int i) {
  if (i <= 0) return i;
  final open = source.lastIndexOf('[', i - 1);
  if (open < 0) return i;
  final close = source.indexOf(']', open);
  if (close < 0) return i;
  return close >= i ? open : i;
}
