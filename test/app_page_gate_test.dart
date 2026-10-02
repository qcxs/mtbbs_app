import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/app/app_page_gate.dart';
import 'package:mtbbs/core/app/site_store.dart';

/// 「页面接管」开关：页面注册表、appPath ↔ 站内 URL 互查、以及唯一决策点
/// [appPageRedirect]（GoRouter 顶层 redirect 调它）。
void main() {
  SiteStore.instance.init();
  final base = SiteStore.instance.baseUrl;

  setUp(() {
    applyDisabledAppPages(const <String>{}); // 每个用例前复位为"全部开启"
    applyBrowserOnlyMode(false); // 复位降级模式
  });

  group('featureIdOf - App 路径 → 页面 id', () {
    test('内容页命中（带 query 也能识别）', () {
      expect(featureIdOf('/thread/123?page=2'), 'thread');
      expect(featureIdOf('/user/88062'), 'user');
      expect(featureIdOf('/forum?fid=42'), 'forum');
      expect(featureIdOf('/search/result?kw=abc'), 'search');
      expect(featureIdOf('/my-threads?type=reply'), 'myThread');
      expect(featureIdOf('/favorite'), 'favorite');
      expect(featureIdOf('/friends?uid=1'), 'friend');
      expect(featureIdOf('/follow?type=follower'), 'follow');
      expect(featureIdOf('/online'), 'online');
      expect(featureIdOf('/darkroom'), 'darkroom');
      expect(featureIdOf('/pm/chat?touid=1'), 'pm');
      expect(featureIdOf('/editor?type=post&fid=2'), 'editor');
    });

    test('非内容页返回 null（不受开关影响）', () {
      for (final p in [
        '/',
        '/guide',
        '/message',
        '/settings',
        '/settings/editor',
        '/history',
        // 搜索中心（站内搜索/Bing/打开链接/找用户/历史）不是"站内搜索结果页"，
        // 整页受开关影响会把其它功能一起废掉
        '/search',
        '/browser?url=x&intercept=false',
      ]) {
        expect(featureIdOf(p), isNull, reason: p);
      }
    });
  });

  group('siteUrlFor - App 路径 → 站内 URL', () {
    test('帖子详情', () {
      expect(
        siteUrlFor('/thread/123'),
        '$base/forum.php?mod=viewthread&tid=123',
      );
      expect(
        siteUrlFor('/thread/123?page=3'),
        '$base/forum.php?mod=viewthread&tid=123&page=3',
      );
    });

    test('用户主页（self 退化为资料页）', () {
      expect(
        siteUrlFor('/user/456'),
        '$base/home.php?mod=space&uid=456&do=profile&from=space',
      );
      expect(siteUrlFor('/user/self'), '$base/home.php?mod=space&do=profile');
    });

    test('版块：顶层 /forum 无 fid → 算不出 URL', () {
      expect(
        siteUrlFor('/forum?fid=42'),
        '$base/forum.php?mod=forumdisplay&fid=42',
      );
      expect(siteUrlFor('/forum'), isNull);
    });

    test('好友 / 关注 / 我的帖子 / 搜索', () {
      expect(
        siteUrlFor('/friends'),
        '$base/home.php?mod=space&do=friend&view=me&from=space',
      );
      expect(
        siteUrlFor('/friends?uid=9&page=2'),
        '$base/home.php?mod=space&uid=9&do=friend&from=space&page=2',
      );
      expect(
        siteUrlFor('/follow?type=follower&uid=9'),
        '$base/home.php?mod=follow&do=follower&uid=9',
      );
      expect(
        siteUrlFor('/my-threads?type=reply&uid=9'),
        '$base/home.php?mod=space&do=thread&uid=9&type=reply',
      );
      expect(
        siteUrlFor('/search/result?kw=abc'),
        '$base/search.php?mod=forum&srchtxt=abc&searchsubmit=yes',
      );
      // 搜索中心入口页不参与回退（无对应单页 URL）
      expect(siteUrlFor('/search'), isNull);
    });

    test('编辑器按类型映射（缺参返回 null）', () {
      expect(
        siteUrlFor('/editor?type=post&fid=2'),
        '$base/forum.php?mod=post&action=newthread&fid=2',
      );
      expect(
        siteUrlFor('/editor?type=comment&tid=5'),
        '$base/forum.php?mod=post&action=reply&tid=5',
      );
      expect(
        siteUrlFor('/editor?type=editPost&tid=5&pid=7'),
        '$base/forum.php?mod=post&action=edit&tid=5&pid=7',
      );
      expect(siteUrlFor('/editor?type=comment'), isNull);
    });
  });

  group('appPageRedirect - 唯一决策点', () {
    test('默认全部开启 → 一律放行（null）', () {
      expect(appPageRedirect('/thread/123'), isNull);
      expect(appPageRedirect('/user/1'), isNull);
      expect(appPageRedirect('/editor?type=post&fid=2'), isNull);
    });

    test('非内容页 / 无对应 URL → 放行', () {
      expect(appPageRedirect('/guide'), isNull);
      expect(appPageRedirect('/settings'), isNull);
      expect(appPageRedirect('/forum'), isNull); // 顶层社区无单页 URL
    });

    test('关闭某页 → 回退内置浏览器（URL 已编码 + intercept=false）', () {
      applyDisabledAppPages({'thread'});
      final target = appPageRedirect('/thread/123');
      expect(
        target,
        '/browser?url=${Uri.encodeComponent('$base/forum.php?mod=viewthread&tid=123')}&intercept=false',
      );
      // 未关闭的页面不受影响
      expect(appPageRedirect('/user/1'), isNull);
    });

    test('关闭但算不出站内地址 → 仍走 App（不硬凑地址）', () {
      applyDisabledAppPages({'editor'});
      expect(appPageRedirect('/editor?type=comment'), isNull);
    });

    test('关闭"站内搜索结果"不影响搜索中心入口页', () {
      applyDisabledAppPages({'search'});
      expect(appPageRedirect('/search'), isNull); // 入口页照常进 App
      expect(
        appPageRedirect('/search/result?kw=abc'),
        isNotNull, // 结果页才回退浏览器
      );
    });

    test('PC 专属页（在线用户 / 小黑屋）回退时带 ua=pc', () {
      applyDisabledAppPages({'online', 'darkroom'});
      expect(
        appPageRedirect('/online'),
        '/browser?url=${Uri.encodeComponent('$base/forum.php?showoldetails=yes')}&ua=pc&intercept=false',
      );
      expect(appPageRedirect('/darkroom'), contains('&ua=pc'));
      // 普通页不受影响，不带 ua=pc
      applyDisabledAppPages({'thread'});
      expect(appPageRedirect('/thread/1'), isNot(contains('ua=pc')));
    });
  });

  group('终极降级（browserOnlyMode）', () {
    test('开启后除浏览器 / 设置外全部走浏览器', () {
      applyBrowserOnlyMode(true);
      // 有站内地址的内容页 → 用该页地址
      expect(appPageRedirect('/thread/123'), contains('/browser?url='));
      expect(
        appPageRedirect('/thread/123'),
        contains(Uri.encodeComponent('tid=123')),
      );
      // Tab 等算不出地址的页 → 退化到站点首页（浏览器至少能打开）
      expect(
        appPageRedirect('/guide'),
        '/browser?url=${Uri.encodeComponent(base)}&intercept=false',
      );
      // 浏览器自身与设置必须放行，否则用户改不回来
      expect(appPageRedirect('/browser?url=x&intercept=false'), isNull);
      expect(appPageRedirect('/settings'), isNull);
      expect(appPageRedirect('/settings/cache'), isNull);
    });

    test('PC 专属页在降级模式下仍带 ua=pc', () {
      applyBrowserOnlyMode(true);
      expect(appPageRedirect('/online'), contains('&ua=pc'));
      expect(appPageRedirect('/thread/1'), isNot(contains('ua=pc')));
    });

    test('关闭降级后恢复正常（逐页开关重新生效）', () {
      applyBrowserOnlyMode(false);
      expect(appPageRedirect('/thread/123'), isNull);
      applyDisabledAppPages({'thread'});
      expect(appPageRedirect('/thread/123'), contains('/browser?url='));
    });

    test('isBrowserOnlyExempt：放行浏览器与设置', () {
      expect(isBrowserOnlyExempt('/browser?url=x'), isTrue);
      expect(isBrowserOnlyExempt('/settings/editor'), isTrue);
      expect(isBrowserOnlyExempt('/thread/1'), isFalse);
      expect(isBrowserOnlyExempt('/guide'), isFalse);
    });
  });

  group('开关状态', () {
    test('默认全部开启', () {
      for (final p in appPages) {
        expect(appPageEnabled(p.id), isTrue, reason: p.id);
      }
    });

    test('applyDisabledAppPages 过滤不在注册表内的 id', () {
      applyDisabledAppPages({'thread', '不存在的页面'});
      expect(appPageEnabled('thread'), isFalse);
      expect(disabledAppPages, {'thread'});
    });
  });
}
