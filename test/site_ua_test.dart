import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/config/site_config.dart';

void main() {
  group('Site UA 模型', () {
    test('默认 userAgent 为空，effectiveUserAgent 回退到 uaAndroid', () {
      const site = Site(
        name: '测试',
        baseUrl: 'https://example.com',
        loginPagePath: '/login',
        forums: {},
        defaultForumOrder: [],
      );
      expect(site.userAgent, isEmpty);
      expect(site.effectiveUserAgent, Site.uaAndroid);
      expect(site.isMobileUA, isTrue);
    });

    test('设置 pc ua 后 isMobileUA 返回 false', () {
      const site = Site(
        name: '测试',
        baseUrl: 'https://example.com',
        loginPagePath: '/login',
        forums: {},
        defaultForumOrder: [],
        userAgent: Site.uaPc,
      );
      expect(site.effectiveUserAgent, Site.uaPc);
      expect(site.isMobileUA, isFalse);
    });

    test('设置 android ua 后 isMobileUA 返回 true', () {
      const site = Site(
        name: '测试',
        baseUrl: 'https://example.com',
        loginPagePath: '/login',
        forums: {},
        defaultForumOrder: [],
        userAgent: Site.uaAndroid,
      );
      expect(site.isMobileUA, isTrue);
    });

    test('toJson / fromJson 正确持久化 userAgent', () {
      const original = Site(
        name: 'MT论坛',
        baseUrl: 'https://bbs.binmt.cc',
        loginPagePath: '/member.php?mod=logging&action=login',
        forums: {},
        defaultForumOrder: [],
        userAgent: Site.uaPc,
      );
      final json = original.toJson();
      expect(json['userAgent'], Site.uaPc);

      final restored = Site.fromJson(json);
      expect(restored.userAgent, Site.uaPc);
      expect(restored.isMobileUA, isFalse);
    });

    test('toJson / fromJson userAgent 为空时省略', () {
      const original = Site(
        name: 'MT论坛',
        baseUrl: 'https://bbs.binmt.cc',
        loginPagePath: '/login',
        forums: {},
        defaultForumOrder: [],
      );
      final json = original.toJson();
      expect(json.containsKey('userAgent'), isFalse);

      final restored = Site.fromJson(json);
      expect(restored.userAgent, isEmpty);
    });
  });
}
