import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/parser/bbcode_list_edit.dart';

void main() {
  group('toListItems', () {
    test('每行转成一项', () {
      expect(toListItems('甲\n乙\n丙'), '\n[*]甲\n[*]乙\n[*]丙\n');
    });

    test('空行被丢弃（否则会渲染出多余空项）', () {
      expect(toListItems('甲\n\n乙\n'), '\n[*]甲\n[*]乙\n');
    });

    test('行首尾空白被去掉', () {
      expect(toListItems('  甲  \n\t乙'), '\n[*]甲\n[*]乙\n');
    });

    test('空文本产出空串', () {
      expect(toListItems(''), '');
      expect(toListItems('   \n\n '), '');
    });

    test('单行也能成项', () {
      expect(toListItems('只有一行'), '\n[*]只有一行\n');
    });
  });

  group('fromListItems', () {
    test('去掉项标记后按行还原', () {
      expect(fromListItems('\n[*]甲\n[*]乙\n'), '甲\n乙');
    });

    test('[/*] 项结束标记也去掉', () {
      expect(fromListItems('[*]甲[/*]\n[*]乙'), '甲\n乙');
    });

    test('空行被丢弃', () {
      expect(fromListItems('\n[*]甲\n\n[*]乙\n'), '甲\n乙');
    });

    test('没有项标记时原样规范化', () {
      expect(fromListItems('  甲  \n乙'), '甲\n乙');
    });
  });

  group('往返', () {
    test('toListItems → fromListItems 还原为规范化纯文本', () {
      const original = '甲\n乙\n丙';
      expect(fromListItems(toListItems(original)), original);
    });

    test('多项文本往返稳定', () {
      const original = '第一行内容\n第二行内容';
      final once = toListItems(original);
      final twice = toListItems(fromListItems(once));
      expect(twice, once);
    });
  });

  group('handleListEnter —— 非列表块一律不接管', () {
    test('普通文本', () {
      expect(handleListEnter('普通文本', 2), isNull);
    });

    test('引用块', () {
      expect(handleListEnter('[quote]甲[/quote]', 8), isNull);
    });

    test('列表前没有 [*]（光标在 [list] 与首个 [*] 之间）不接管', () {
      //           0123456789
      const raw = '[list]\n[*]甲[/list]';
      expect(handleListEnter(raw, 3), isNull);
    });

    test('光标越界不接管', () {
      expect(handleListEnter('[list]\n[*]甲\n[/list]', 999), isNull);
    });
  });

  group('handleListEnter —— 项末尾回车自动起新项', () {
    test('末项末尾 → 补 [*] 且光标落在新标记之后', () {
      //             0123456789012345
      const raw = '[list=1]\n[*]甲\n[/list]';
      final r = handleListEnter(raw, 13); // '甲' 之后
      expect(r, isNotNull);
      expect(r!.exitList, isFalse);
      expect(r.text, '[list=1]\n[*]甲\n[*]\n[/list]');
      expect(r.cursor, 17, reason: '光标应停在新 [*] 之后，可直接输入');
    });

    test('中间项的末尾 → 同样在其后补 [*]', () {
      const raw = '[list]\n[*]甲\n[*]乙\n[/list]';
      // '甲' 之后（下标 11）才是项末尾；下标 12 已在下一项标记前
      final r = handleListEnter(raw, 11);
      expect(r!.exitList, isFalse);
      expect(r.text, '[list]\n[*]甲\n[*]\n[*]乙\n[/list]');
    });

    test('项内还有内容（光标在项中间）→ 不接管，交给普通换行', () {
      const raw = '[list]\n[*]甲乙\n[/list]';
      expect(handleListEnter(raw, 11), isNull); // '甲' 与 '乙' 之间
    });

    test('无序列表同样生效', () {
      const raw = '[list]\n[*]甲\n[/list]';
      final r = handleListEnter(raw, 11);
      expect(r!.exitList, isFalse);
      expect(r.text, '[list]\n[*]甲\n[*]\n[/list]');
    });
  });

  group('handleListEnter —— 空项回车跳出列表', () {
    test('空项 → 去掉空项标记，光标落到列表之后', () {
      const raw = '[list=1]\n[*]甲\n[*]\n[/list]';
      final r = handleListEnter(raw, 17); // 空 [*] 之后
      expect(r!.exitList, isTrue);
      expect(r.text, '[list=1]\n[*]甲\n[/list]');
      expect(r.cursor, r.text.length);
    });

    test('唯一项就是空的 → 连 [list] 外壳一起去掉', () {
      const raw = '[list]\n[*]\n[/list]';
      final r = handleListEnter(raw, 10);
      expect(r!.exitList, isTrue);
      expect(r.text.contains('[list]'), isFalse, reason: '空列表渲染出来只有空行');
      expect(r.text.contains('[*]'), isFalse);
    });

    test('有序列表外壳也去掉', () {
      final r = handleListEnter('[list=1]\n[*]\n[/list]', 13);
      expect(r!.exitList, isTrue);
      expect(r.text.contains('[list'), isFalse);
    });
  });
}
