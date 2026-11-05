import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/app/default_config.dart';
import 'package:mtbbs/models/settings/site_settings.dart';

/// 站点级默认设置（assets/config/site_defaults.json）：
/// 52pojie 只默认关闭涉及编辑/写入的页面接管；只读页面（含未适配的）仍走 App。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await DefaultConfig.instance.load();
  });

  test('52pojie 默认只关闭编辑相关页面', () {
    final pages = SitePageGateSettings.defaultsFor('www.52pojie.cn');
    expect(pages.browserOnly, isFalse);
    expect(
      pages.disabledPageIds,
      unorderedEquals(['editor', 'wall', 'pm']),
    );
    for (final id in [
      'thread',
      'user',
      'forum',
      'search',
      'myThread',
      'favorite',
      'friend',
      'follow',
      'online',
      'darkroom',
      'groups',
      'creditLog',
      'ranklist',
    ]) {
      expect(pages.disabledPageIds, isNot(contains(id)), reason: '$id 是只读页');
    }
  });

  test('其它站点仍默认全部 App 接管', () {
    expect(
      SitePageGateSettings.defaultsFor('bbs.binmt.cc').disabledPageIds,
      isEmpty,
    );
  });

  test('已保存的站点设置优先于默认值', () {
    final saved = SiteSettings.fromMap('www.52pojie.cn', {
      'pages': {'disabledPageIds': <String>[]},
    });
    expect(saved.pages.disabledPageIds, isEmpty);
  });

  test('旧文档缺少 pages 段时用站点默认值兜底', () {
    final legacy = SiteSettings.fromMap('www.52pojie.cn', {
      'host': 'www.52pojie.cn',
    });
    expect(legacy.pages.disabledPageIds, contains('editor'));
  });
}
