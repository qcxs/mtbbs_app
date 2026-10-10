import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/utils/url_router.dart';

/// UrlRouter：Discuz URL → App 路由，以及"链接 → 落地页"的唯一决策点。
///
/// 覆盖回归：`forum.php?mod=guide` 曾未映射，导致系统「打开方式」进入 App 时
/// 拿完整 URL 去匹配路由表（另一种成因见 router.dart 的
/// `overridePlatformDefaultLocation`）。
void main() {
  setUpAll(() {
    // 默认站点为 MT 论坛（bbs.binmt.cc）；parse 依赖当前站点判断"是否他站"
    SiteStore.instance.init();
  });

  group('parse - URL → App 路由', () {
    test('帖子伪静态 → /thread/{tid}', () {
      expect(
        UrlRouter.parse('https://bbs.binmt.cc/thread-173540-1-1.html').appPath,
        '/thread/173540',
      );
    });

    test('导读 forum.php?mod=guide → /guide', () {
      final result = UrlRouter.parse(
        'https://bbs.binmt.cc/forum.php?mod=guide&view=newthread&index=1',
      );
      expect(result.appPath, '/guide');
      expect(result.isOtherSite, isFalse);
    });

    test('用户主页 home.php?mod=space&uid → /user/{uid}', () {
      expect(
        UrlRouter.parse(
          'https://bbs.binmt.cc/home.php?mod=space&uid=88062',
        ).appPath,
        '/user/88062',
      );
    });

    test('定位回复 findpost(ptid+pid) → /thread/{tid}?pid=', () {
      expect(
        UrlRouter.parse(
          'https://bbs.binmt.cc/forum.php?mod=redirect&goto=findpost&pid=11933888&ptid=174303',
        ).appPath,
        '/thread/174303?pid=11933888',
      );
    });

    test('其他站点的链接会被标记为他站', () {
      final result = UrlRouter.parse('https://example.com/thread-1-1-1.html');
      expect(result.isOtherSite, isTrue);
    });

    test('私信会话 home.php?mod=space&do=pm&subop=view&touid → /pm/chat', () {
      expect(
        UrlRouter.parse(
          'https://bbs.binmt.cc/home.php?mod=space&do=pm&subop=view&touid=152009#last',
        ).appPath,
        '/pm/chat?touid=152009',
      );
    });

    test('私信列表 home.php?mod=space&do=pm → /message', () {
      expect(
        UrlRouter.parse(
          'https://bbs.binmt.cc/home.php?mod=space&do=pm',
        ).appPath,
        '/message',
      );
    });

    test('发私信页 home.php?mod=spacecp&ac=pm&op=showmsg&touid → /pm/chat', () {
      expect(
        UrlRouter.parse(
          'https://bbs.binmt.cc/home.php?mod=spacecp&ac=pm&op=showmsg&touid=88062',
        ).appPath,
        '/pm/chat?touid=88062',
      );
    });

    test('积分记录 home.php?mod=spacecp&ac=credit&op=log → /credit-log', () {
      expect(
        UrlRouter.parse(
          'https://bbs.binmt.cc/home.php?mod=spacecp&ac=credit&op=log&page=2',
        ).appPath,
        '/credit-log',
      );
    });

    test('积分记录带类型筛选 exttype → /credit-log?exttype=', () {
      expect(
        UrlRouter.parse(
          'https://bbs.binmt.cc/home.php?mod=spacecp&ac=credit&op=log&exttype=2',
        ).appPath,
        '/credit-log?exttype=2',
      );
    });

    test('积分记录带操作筛选 optype → /credit-log?optype=', () {
      expect(
        UrlRouter.parse(
          'https://bbs.binmt.cc/home.php?mod=spacecp&ac=credit&op=log&optype=PRC',
        ).appPath,
        '/credit-log?optype=PRC',
      );
    });

    test('圈子首页 group.php → /groups', () {
      expect(
        UrlRouter.parse('https://bbs.binmt.cc/group.php?hot=yes').appPath,
        '/groups',
      );
    });

    test('圈子分类 group.php?gid → /groups/category', () {
      expect(
        UrlRouter.parse('https://bbs.binmt.cc/group.php?gid=3').appPath,
        '/groups/category?gid=3',
      );
    });

    test('圈子内容伪静态 group-{gid}-1.html → /groups/content', () {
      expect(
        UrlRouter.parse('https://bbs.binmt.cc/group-57-1.html').appPath,
        '/groups/content?gid=57',
      );
    });
  });

  group('resolveTarget - 唯一决策点', () {
    test('本站可映射链接 → App 内路径', () {
      expect(
        UrlRouter.resolveTarget(
          'https://bbs.binmt.cc/forum.php?mod=guide&view=newthread&index=1',
        ),
        '/guide',
      );
    });

    test('本站但无法映射 → 内置浏览器兜底（带 intercept=false，避免二次拦截）', () {
      final target = UrlRouter.resolveTarget(
        'https://bbs.binmt.cc/misc.php?mod=faq',
      );
      expect(target, startsWith('/browser?url='));
      expect(target, contains('intercept=false'));
    });

    test('其他站点 → 内置浏览器兜底（不串站点）', () {
      final target = UrlRouter.resolveTarget(
        'https://example.com/thread-1-1-1.html',
      );
      expect(target, startsWith('/browser?url='));
    });

    test('App 内路径原样返回', () {
      expect(UrlRouter.resolveTarget('/home'), '/home');
    });

    test('空串 → null（调用方不跳转）', () {
      expect(UrlRouter.resolveTarget('   '), isNull);
    });
  });
}
