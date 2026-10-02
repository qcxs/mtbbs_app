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
      final cookies = toJarCookies([
        Cookie(name: 'abc_sid', value: 'y'),
      ], siteUri);

      expect(cookies.first.domain, '.bbs.binmt.cc');
      expect(cookies.first.path, '/');
      expect(cookies.first.secure, true);
    });

    test('一律按会话 cookie：不携带 expires（各端 expiresDate 单位都不可信）', () {
      final ms = DateTime(2030, 1, 2).millisecondsSinceEpoch;
      final cookies = toJarCookies([
        Cookie(name: 'future_ms', value: 'a', expiresDate: ms), // 将来（毫秒）
        Cookie(
          name: 'seconds',
          value: 'b',
          expiresDate: ms ~/ 1000,
        ), // Windows：秒
        // Android：currentTimeMillis() + maxAge，而 maxAge 是秒 → "现在 + N 毫秒"
        Cookie(
          name: 'android_maxage',
          value: 'c',
          expiresDate: DateTime.now().millisecondsSinceEpoch + 1800,
        ),
        Cookie(name: 'session', value: 'd'), // 无过期时间
      ], siteUri);

      expect(cookies.map((c) => c.name).toList(), [
        'future_ms',
        'seconds',
        'android_maxage',
        'session',
      ]);
      // 带上 expires 只会在落盘时被 cookie_jar 静默丢弃（见 docs/07 #73）
      for (final c in cookies) {
        expect(c.expires, isNull);
      }
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

  group('核心 / 临时 Cookie 分类', () {
    test('前缀优先取自 Discuz 判定登录的 {prefix}auth', () {
      expect(
        inferCookiePrefix(['acw_tc', 'cQWy_2132_auth', 'cQWy_2132_sid']),
        'cQWy_2132_',
      );
    });

    test('没有 auth 时按统计取出现 ≥2 次的下划线前缀，否则不筛', () {
      expect(
        inferCookiePrefix(['cQWy_2132_sid', 'cQWy_2132_lastvisit', 'acw_tc']),
        'cQWy_2132_',
      );
      expect(inferCookiePrefix(['a', 'b']), '');
    });

    test('前缀为空 = 未识别，一律视为核心（不筛选）', () {
      expect(isCoreCookie('acw_tc', ''), isTrue);
      expect(isCoreCookie('acw_tc', 'cQWy_2132_'), isFalse);
      expect(isCoreCookie('cQWy_2132_sid', 'cQWy_2132_'), isTrue);
    });

    test('登录态串只留核心 cookie，防护 cookie 被剔除', () {
      const raw =
          'acw_tc=74b1fe99x; cdn_sec_tc=74b1fe99x; acw_sc__v2=6abf106bx; '
          'cQWy_2132_auth=abc; cQWy_2132_saltkey=x8AMbtEO';

      expect(
        coreCookiesOf(raw),
        'cQWy_2132_auth=abc; cQWy_2132_saltkey=x8AMbtEO',
      );
    });
  });
}
