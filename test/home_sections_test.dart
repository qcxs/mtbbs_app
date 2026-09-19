import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/models/managed_item.dart';
import 'package:mtbbs/providers/settings_provider.dart';

/// 首页区块状态要靠 `ManagedItem` 的 JSON 往返才能持久化，而展开状态
/// 存在自定义字段 `data['expanded']` 里 —— 这是往返中最容易丢的东西。
/// 这里守住：默认值符合预期 + 往返后顺序/显隐/展开状态都不变。
void main() {
  test('默认区块：快捷链接 / 版块 / 排行展开，RSS 隐藏且折叠', () {
    final sections = SettingsProvider.defaultHomeSections();
    expect(sections.map((e) => e.id), ['shortcuts', 'forums', 'rank', 'rss']);

    bool expandedOf(String id) => SettingsProvider.homeSectionExpanded(
      sections.firstWhere((e) => e.id == id),
    );

    expect(expandedOf('shortcuts'), isTrue);
    expect(expandedOf('forums'), isTrue);
    expect(expandedOf('rank'), isTrue);

    final rss = sections.firstWhere((e) => e.id == 'rss');
    expect(rss.visible, isFalse, reason: 'RSS 与导读 Tab 内容重合，默认隐藏');
    expect(expandedOf('rss'), isFalse);
  });

  test('JSON 往返后顺序、显隐、展开状态都不丢', () {
    final sections = SettingsProvider.defaultHomeSections();
    // 模拟用户在设置面板里改过的状态：关掉快捷链接、打开 RSS
    sections[0] = sections[0].copyWith(
      visible: false,
      data: {'expanded': false},
    );
    final rssIndex = sections.indexWhere((e) => e.id == 'rss');
    sections[rssIndex] = sections[rssIndex].copyWith(
      visible: true,
      data: {'expanded': true},
    );

    final restored = ManagedItem.decodeList(ManagedItem.encodeList(sections));

    expect(restored.map((e) => e.id), ['shortcuts', 'forums', 'rank', 'rss']);
    expect(restored[0].visible, isFalse);
    expect(SettingsProvider.homeSectionExpanded(restored[0]), isFalse);
    expect(restored[rssIndex].visible, isTrue);
    expect(SettingsProvider.homeSectionExpanded(restored[rssIndex]), isTrue);
  });
}
