import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/config/toolbar_config.dart';
import 'package:mtbbs/core/app/default_config.dart';
import 'package:mtbbs/core/utils/shortcut_helper.dart';

/// 快捷键解析与"默认值一致性"测试。
///
/// 背景：默认快捷键曾在 `assets/config/toolbar.json` 与
/// `toolbar_config.dart` 两处各写一份（后者是 JSON 读取失败时的兜底），
/// 而 `DefaultConfig` 又是「不可识别的主键静默回退成 Escape」——
/// 于是 `Ctrl+\` 实际绑到了 `Ctrl+Escape` 上，且没人发现。
/// 这里用两条测试守住这类问题：解析不认识就返回 null；两处默认值必须逐字相同。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ShortcutHelper.parse', () {
    SingleActivator single(ShortcutActivator? a) {
      expect(a, isNotNull);
      return a! as SingleActivator;
    }

    test('字母 + Ctrl', () {
      final s = single(ShortcutHelper.parse('Ctrl+B'));
      expect(s.trigger, LogicalKeyboardKey.keyB);
      expect(s.control, isTrue);
      expect(s.shift, isFalse);
    });

    test('Alt + Shift + 数字（Typora 的删除线）', () {
      final s = single(ShortcutHelper.parse('Alt+Shift+5'));
      expect(s.trigger, LogicalKeyboardKey.digit5);
      expect(s.alt, isTrue);
      expect(s.shift, isTrue);
      expect(s.control, isFalse);
    });

    test('方括号（Typora 的列表快捷键）', () {
      expect(
        single(ShortcutHelper.parse('Ctrl+Shift+]')).trigger,
        LogicalKeyboardKey.bracketRight,
      );
      expect(
        single(ShortcutHelper.parse('Ctrl+Shift+[')).trigger,
        LogicalKeyboardKey.bracketLeft,
      );
    });

    test('反斜杠（Typora 的清除格式）', () {
      expect(
        single(ShortcutHelper.parse('Ctrl+\\')).trigger,
        LogicalKeyboardKey.backslash,
      );
    });

    test('功能键与 Escape', () {
      expect(single(ShortcutHelper.parse('F5')).trigger, LogicalKeyboardKey.f5);
      expect(
        single(ShortcutHelper.parse('Escape')).trigger,
        LogicalKeyboardKey.escape,
      );
    });

    test('空串 → null', () {
      expect(ShortcutHelper.parse(''), isNull);
    });

    test('无法识别的主键 → null，而不是静默绑到别的键', () {
      expect(ShortcutHelper.parse('Ctrl+Nonsense'), isNull);
      expect(ShortcutHelper.parse('Ctrl+中'), isNull);
    });
  });

  group('默认值与 Typora 对齐', () {
    /// Typora（Windows）官方默认表里、本 app 有对应能力的项。
    ///
    /// 来源见 docs/05「默认快捷键与 Typora 对齐」。
    const typoraDefaults = <String, String>{
      'bold': 'Ctrl+B',
      'italic': 'Ctrl+I',
      'underline': 'Ctrl+U',
      'strikethrough': 'Alt+Shift+5',
      'link': 'Ctrl+K',
      'image': 'Ctrl+Shift+I',
      'clearStyles': 'Ctrl+\\',
      'table': 'Ctrl+T',
      'code': 'Ctrl+Shift+K',
      'quote': 'Ctrl+Shift+Q',
      'listOl': 'Ctrl+Shift+[',
      'listUl': 'Ctrl+Shift+]',
    };

    setUpAll(() async {
      await DefaultConfig.instance.load();
    });

    test('每个 Typora 对应项的默认快捷键一致', () {
      final actual = defaultToolbarShortcuts();
      for (final e in typoraDefaults.entries) {
        expect(actual[e.key], e.value, reason: '${e.key} 应与 Typora 一致');
      }
    });

    test('所有默认快捷键都能解析（不会静默失效）', () {
      for (final e in defaultToolbarShortcuts().entries) {
        expect(
          ShortcutHelper.parse(e.value),
          isNotNull,
          reason: '${e.key} 的 "${e.value}" 解析不出来，等于没绑',
        );
      }
    });

    test('toolbar.json 与 toolbar_config.dart 的兜底值必须一致', () {
      final fromJson = defaultToolbarShortcuts();
      final fromCode = {
        for (final c in allToolbarItemConfigs)
          if (c.defaultShortcut.isNotEmpty) c.id: c.defaultShortcut,
      };
      expect(fromJson, fromCode, reason: '两处默认值漂移过（导致快捷键实际绑错），必须逐字相同');
    });

    test('toolbar.json 与 toolbar_config.dart 的项集合一致', () {
      final jsonIds = defaultToolbarItems().map((e) => e.id).toSet();
      final codeIds = allToolbarItemConfigs.map((e) => e.id).toSet();
      expect(
        jsonIds,
        codeIds,
        reason: 'toolbar.json 里没有的项拿不到 ToolbarAction，按钮点了没反应',
      );
    });
  });
}
