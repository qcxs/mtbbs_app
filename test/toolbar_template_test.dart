import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/config/toolbar_config.dart';
import 'package:mtbbs/core/app/default_config.dart';
import 'package:mtbbs/widgets/bbcode/bbcode_controller.dart';

void main() {
  const token = kSelectTextToken;

  group('applyTemplate — $token 占位符', () {
    test('有选中：用选中文本填充并整体替换选区', () {
      final ctl = BBCodeController(text: '前面 重点 后面');
      ctl.selection = const TextSelection(baseOffset: 3, extentOffset: 5);
      final wrapped = ctl.applyTemplate('[b]$token[/b]');
      expect(wrapped, isTrue);
      expect(ctl.text, '前面 [b]重点[/b] 后面');
    });

    test('无选中：占位符置空，光标落在标签中间', () {
      final ctl = BBCodeController(text: 'abc');
      ctl.selection = const TextSelection.collapsed(offset: 3);
      final wrapped = ctl.applyTemplate('[b]$token[/b]');
      expect(wrapped, isFalse);
      expect(ctl.text, 'abc[b][/b]');
      expect(ctl.selection.baseOffset, 3 + '[b]'.length);
    });

    test('选中首尾空格被 trim，仅替换 trim 后的范围', () {
      final ctl = BBCodeController(text: '  x  ');
      ctl.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      ctl.applyTemplate('[i]$token[/i]');
      expect(ctl.text, '  [i]x[/i]  ');
    });

    test('无占位符：光标落在插入内容之后', () {
      final ctl = BBCodeController(text: 'ab');
      ctl.selection = const TextSelection.collapsed(offset: 2);
      ctl.applyTemplate('[hr]');
      expect(ctl.text, 'ab[hr]');
      expect(ctl.selection.baseOffset, 2 + '[hr]'.length);
    });

    test('自定义模板（标题）：[size=4][b]…[/b][/size]', () {
      final ctl = BBCodeController(text: '标题文字');
      ctl.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
      ctl.applyTemplate('[size=4][b]$token[/b][/size]');
      expect(ctl.text, '[size=4][b]标题文字[/b][/size]');
    });
  });

  group('默认工具栏：模板项数据完整', () {
    setUpAll(() async {
      await DefaultConfig.instance.load();
    });

    test('每个模板项都带 group 与 label', () {
      final items = defaultToolbarItems();
      final templateItems = items
          .where((e) => toolbarTemplateOf(e) != null)
          .toList();
      expect(templateItems, isNotEmpty);
      for (final item in templateItems) {
        expect(item.data?['group'], isNotEmpty, reason: '${item.id} 缺 group');
        expect(toolbarLabelOf(item), isNotEmpty, reason: '${item.id} 缺 label');
      }
    });

    test('模板项与枚举解耦：resolveToolbarAction 返回 null，但可取到模板', () {
      expect(resolveToolbarAction('bold'), isNull);
      final bold = defaultToolbarItems().firstWhere((e) => e.id == 'bold');
      expect(toolbarTemplateOf(bold), '[b]${kSelectTextToken}[/b]');
    });

    test('复杂项仍能解析出动作', () {
      expect(resolveToolbarAction('image'), isNotNull);
      expect(resolveToolbarAction('emoji'), isNotNull);
    });
  });
}
