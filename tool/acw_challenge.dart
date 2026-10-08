/// 阿里云 ESA「acw_sc__v2」挑战的纯算法自解（供探针使用，不依赖 JS 引擎）。
///
/// 站点（MT 论坛）现由 ESA 前置，未通过挑战时返回 200 + 几 KB 的挑战页：
///
/// ```
/// <html><script>var arg1='<40位hex>';(function(a,c){…})();…</script></html>
/// ```
///
/// 页面 JS 会用 `arg1` 算出 `acw_sc__v2` 写回 Cookie 并重载。算法是固定的两步
/// （置乱表 + 与固定 key 逐字节异或），与浏览器无关，因此 Dart 侧可原样复现——
/// 这正是探针能"自己过验证"的依据（见 docs/10）。
library;

/// 固定异或 key（40 位 hex，跨站点/跨时间不变）
const String _kXorKey = '3000176000856006061501533003690027800375';

/// 位置置乱表（`unsbox` 步骤用；1-based，长度 40）
const List<int> _kPerm = [
  15,
  35,
  29,
  24,
  33,
  16,
  1,
  38,
  10,
  9,
  19,
  31,
  40,
  27,
  22,
  23,
  25,
  13,
  6,
  11,
  39,
  18,
  20,
  8,
  14,
  21,
  32,
  26,
  2,
  30,
  7,
  4,
  17,
  5,
  3,
  28,
  34,
  37,
  12,
  36,
];

/// 从挑战页正文提取 `arg1`；不是挑战页则返回 null。
String? extractAcwArg1(String body) {
  final m = RegExp(
    r"""arg1\s*=\s*['"]([0-9A-Fa-f]{40})['"]""",
  ).firstMatch(body);
  return m?.group(1);
}

/// 由 `arg1` 计算 `acw_sc__v2`（与挑战页 JS 等价）。
///
/// ① `unsbox`：按 [_kPerm] 把 `arg1` 重新排位；
/// ② `hexXor`：与 [_kXorKey] 按字节异或，结果补足两位 hex。
String acwScV2(String arg1) {
  final q = List<String>.filled(_kPerm.length, '');
  for (var i = 0; i < arg1.length; i++) {
    final y = arg1[i];
    for (var z = 0; z < _kPerm.length; z++) {
      if (_kPerm[z] == i + 1) q[z] = y;
    }
  }
  final u = q.join();
  final sb = StringBuffer();
  for (var x = 0; x + 1 < u.length && x + 1 < _kXorKey.length; x += 2) {
    final a =
        int.parse(u.substring(x, x + 2), radix: 16) ^
        int.parse(_kXorKey.substring(x, x + 2), radix: 16);
    sb.write(a.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}
