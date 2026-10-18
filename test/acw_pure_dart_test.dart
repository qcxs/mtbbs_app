import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/app/acw_pure_dart.dart';

void main() {
  const arg1 = '0123456789abcdef0123456789abcdef01234567';

  test('从挑战页提取 arg1', () {
    final html = '<html><script>var arg1=\'$arg1\';(function(){})();</script>';
    expect(extractAcwArg1(html), arg1);
    expect(extractAcwArg1('<html>普通页面</html>'), isNull);
  });

  test('acwScV2 输出 40 位小写 hex', () {
    final value = acwScV2(arg1);
    expect(value, matches(RegExp(r'^[0-9a-f]{40}$')));
  });

  test('同一 arg1 结果稳定', () {
    expect(acwScV2(arg1), acwScV2(arg1));
  });
}
