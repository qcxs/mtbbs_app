import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/core/app/browse_mode.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/mcp/mcp_types.dart';
import 'package:mtbbs/mcp/tools/mcp_tool_registry.dart';

import '../tool/api_scenarios.dart';

/// 「浏览模式」覆盖：默认跟随站点设置；探针（进程级）/ MCP（Zone 级）可临时换 UA。
///
/// 一致性约定（**白名单原则**）：支持移动端的接口必定同时支持 PC，且只是少数；
/// 因此用白名单表达"哪些接口支持 mobile"，其余一律 PC-only。下面的用例锁住白名单，
/// 防止将来新增/删除接口时漏改（文档 docs/03、10、17 与之保持一致）。
void main() {
  SiteStore.instance.init();

  setUp(() => applyStickyBrowseMode(''));
  tearDown(() => applyStickyBrowseMode(''));

  test('normalizeBrowseMode 归一（含别名与非法值）', () {
    expect(normalizeBrowseMode('mobile'), 'mobile');
    expect(normalizeBrowseMode('M'), 'mobile');
    expect(normalizeBrowseMode('pc'), 'desktop');
    expect(normalizeBrowseMode('DeSkToP'), 'desktop');
    expect(normalizeBrowseMode(''), isNull);
    expect(normalizeBrowseMode('default'), isNull);
    expect(normalizeBrowseMode(null), isNull);
  });

  test('无覆盖时跟随站点「浏览模式」', () {
    expect(browseModeOverrideActive(), isFalse);
    expect(resolveRequestUserAgent(), SiteStore.instance.userAgent);
  });

  test('进程级覆盖（探针）：mobile / desktop 切换，清除即失效', () {
    applyStickyBrowseMode('mobile');
    expect(browseModeOverrideActive(), isTrue);
    expect(resolveRequestUserAgent(), Site.uaAndroid);

    applyStickyBrowseMode('pc');
    expect(resolveRequestUserAgent(), Site.uaPc);

    applyStickyBrowseMode('');
    expect(browseModeOverrideActive(), isFalse);
    expect(resolveRequestUserAgent(), SiteStore.instance.userAgent);
  });

  test('Zone 覆盖（MCP 单次调用）：调用内生效、调用后自动失效', () async {
    expect(browseModeOverrideActive(), isFalse);
    await runWithBrowseMode('desktop', () async {
      expect(browseModeOverrideActive(), isTrue);
      expect(resolveRequestUserAgent(), Site.uaPc);
    });
    expect(browseModeOverrideActive(), isFalse);
    expect(resolveRequestUserAgent(), SiteStore.instance.userAgent);
  });

  test('runWithBrowseMode 非法值 = 不覆盖', () async {
    await runWithBrowseMode('xxx', () async {
      expect(browseModeOverrideActive(), isFalse);
    });
  });

  test('一致性：MCP 支持 mobile 的工具恰为约定的 5 个', () {
    final mobile = McpToolRegistry.buildTools(
      () => const McpAccountInfo.guest(),
    ).where((d) => d.mobileSupported).map((d) => d.name).toSet();
    expect(mobile, {
      'list_forum_threads',
      'list_guide_threads',
      'search_forum_threads',
      'list_user_threads',
      'get_user_profile',
    });
  });

  test('一致性：探针支持 mobile 的场景恰为约定的 6 个', () {
    final mobile = scenarios.entries
        .where((e) => e.value.mobileSupported)
        .map((e) => e.key)
        .toSet();
    expect(mobile, {
      'guide.list',
      'forum.list',
      'search.list',
      'my.threads',
      'user.info',
      'debug.http',
    });
  });
}
