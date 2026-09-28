import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/app/cookie_sync.dart';

/// Cookie 反向同步（WebView → Dio）的纯转换逻辑。
///
/// 平台相关的读写在设备上验证；这里锁住转换规则：
/// domain 归一化（避免与已有条目共存导致同名 Cookie 重复下发）、
/// 过期时间换算、非法条目跳过。
void main() {
  final siteUri = Uri.parse('https://bbs.binmt.cc');

  group('WebView Cookie → CookieJar Cookie', () {
    test('domain 归一化为前导点号形式（与 App 自身存 Cookie 的写法一致）', () {
      final cookies = toJarCookies([
        Cookie(name: 'abc_auth', value: 'x', domain: 'bbs.binmt.cc', path: '/'),
      ], siteUri);

      expect(cookies, hasLength(1));
      expect(cookies.first.name, 'abc_auth');
      expect(cookies.first.domain, '.bbs.binmt.cc');
      expect(cookies.first.path, '/');
    });

    test('已带前导点号的 domain 不重复加点', () {
      final cookies = toJarCookies([
        Cookie(name: 'abc_auth', value: 'x', domain: '.binmt.cc'),
      ], siteUri);
      expect(cookies.first.domain, '.binmt.cc');
    });

    test('domain 缺失（部分 Android 设备取不到）时回退站点 host', () {
      final cookies = toJarCookies([Cookie(name: 'abc_sid', value: 'y')], siteUri);

      expect(cookies.first.domain, '.bbs.binmt.cc');
      expect(cookies.first.path, '/');
      expect(cookies.first.secure, true);
    });

    test('过期时间按毫秒转换为 DateTime', () {
      final ms = DateTime(2030, 1, 2).millisecondsSinceEpoch;
      final cookies = toJarCookies([
        Cookie(name: 'a', value: 'b', expiresDate: ms),
      ], siteUri);
      expect(cookies.first.expires?.millisecondsSinceEpoch, ms);
    });

    test('非法条目（值含逗号，dart:io 按 RFC 6265 拒绝）被跳过，不影响其余条目', () {
      final cookies = toJarCookies([
        Cookie(name: 'good', value: 'ok'),
        Cookie(name: 'discuz_lastvisit', value: 't1,t2,t3'),
      ], siteUri);

      expect(cookies.map((c) => c.name).toList(), ['good']);
    });

    test('空名 Cookie 被跳过', () {
      expect(toJarCookies([Cookie(name: '', value: 'x')], siteUri), isEmpty);
    });
  });
}
