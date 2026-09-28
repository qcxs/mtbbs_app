import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/parser/md2bbcode.dart';

/// Markdown → BBCode 转换器单测
///
/// 断言用 `contains` 而非全等：模板可配置，全等会把默认模板的每个字符都锁死。
void main() {
  String conv(
    String md, {
    bool autoNumbering = false,
    bool removeEmoji = false,
  }) => markdownToBbcode(
    md,
    autoNumbering: autoNumbering,
    removeEmoji: removeEmoji,
  );

  test('标题与行内样式', () {
    final out = conv('# 一级\n\n## 二级 **粗** *斜* ~~删~~\n');
    // ignore: avoid_print
    print('--- 标题与行内样式 ---\n$out');
    expect(out, contains('[size=3][b]一级[/b][/size]'));
    expect(out, contains('二级 [b]粗[/b] [i]斜[/i] [s]删[/s]'));
    expect(out, contains('[size=2]'));
    expect(out, isNot(contains('<br>')));
    expect(out, isNot(contains('<')));
  });

  test('标题自动编号', () {
    final out = conv('# A\n\n## B\n\n# C\n', autoNumbering: true);
    // ignore: avoid_print
    print('--- 自动编号 ---\n$out');
    expect(out, contains('1 A'));
    expect(out, contains('1.1 B'));
    expect(out, contains('2 C'));
  });

  test('无序/有序/嵌套列表', () {
    final out = conv('- a\n- b\n\n1. x\n2. y\n\n- p\n  - p1\n');
    // ignore: avoid_print
    print('--- 列表 ---\n$out');
    expect(out, contains('[list]'));
    expect(out, contains('[*]a'));
    expect(out, contains('[list=1]'));
    expect(out, contains('[*]x'));
    expect(out, contains('[*]p[list]'));
    expect(out, contains('[*]p1'));
    expect(out, isNot(contains('\n\n')));
  });

  test('任务列表 → [✓] / [✗]', () {
    final out = conv('- [x] 已完成\n- [ ] 未完成\n');
    // ignore: avoid_print
    print('--- 任务列表 ---\n$out');
    expect(out, contains('[*][✓] 已完成'));
    expect(out, contains('[*][✗] 未完成'));
    expect(out, isNot(contains('input')));
  });

  test('表格', () {
    final out = conv('| A | B |\n| --- | --- |\n| 1 | 2 |\n');
    // ignore: avoid_print
    print('--- 表格 ---\n$out');
    expect(out, contains('[table]'));
    expect(out, contains('[tr]'));
    expect(out, contains('[td]A[/td]'));
    expect(out, contains('[td]1[/td]'));
    expect(out, isNot(contains('|')));
  });

  test('代码块保留内部空行，语言丢弃', () {
    final out = conv(
      '```dart\nvoid main() {\n  print(1);\n\n  print(2);\n}\n```\n',
    );
    // ignore: avoid_print
    print('--- 代码块 ---\n$out');
    expect(out, startsWith('[code]'));
    expect(out, contains('print(1);\n\n  print(2);'));
    expect(out, isNot(contains('dart')));
    expect(out, isNot(contains('\n[/code]')));
  });

  test('行内代码', () {
    final out = conv('这是 `code` 片段\n');
    // ignore: avoid_print
    print('--- 行内代码 ---\n$out');
    expect(out, contains('[backcolor=#f4f4f4]code[/backcolor]'));
  });

  test('链接 / 邮件 / 图片 / 自动链接', () {
    final out = conv(
      '[站点](https://a.com) [邮箱](mailto:x@y.com) ![图](https://i.png)\n\n'
      'https://auto.com\n',
    );
    // ignore: avoid_print
    print('--- 链接 ---\n$out');
    expect(out, contains('[url=https://a.com]站点[/url]'));
    expect(out, contains('[email=x@y.com]邮箱[/email]'));
    expect(out, contains('[img]https://i.png[/img]'));
    expect(out, contains('[url=https://auto.com]https://auto.com[/url]'));
  });

  test('嵌套引用只输出一层 [quote]', () {
    final out = conv('> 外层\n>\n> > 内层\n');
    // ignore: avoid_print
    print('--- 引用 ---\n$out');
    expect(out, contains('[quote]'));
    expect(out, contains('内层'));
    expect('[quote]'.allMatches(out).length, 1);
  });

  test('Front Matter → [free]', () {
    final out = conv('---\ntitle: 你好\ntags: [a, b]\n---\n\n正文\n');
    // ignore: avoid_print
    print('--- Front Matter ---\n$out');
    expect(out, startsWith('[free]'));
    expect(out, contains('title: 你好'));
    expect(out, contains('正文'));
  });

  test('高亮 ==text==', () {
    final out = conv('这是 ==高亮== 文字\n');
    // ignore: avoid_print
    print('--- 高亮 ---\n$out');
    expect(out, contains('[backcolor=#FFFF00]高亮[/backcolor]'));
  });

  test('去除 Emoji', () {
    final out = conv('你好 😀 世界 ❤️\n', removeEmoji: true);
    // ignore: avoid_print
    print('--- 去除 Emoji ---\n$out');
    expect(out, contains('你好'));
    expect(out, isNot(contains('😀')));
    expect(out, isNot(contains('\uFE0F')));
  });

  test('空输入返回空串；裸 HTML 原样透传（已知限制，与 mt-convert 一致）', () {
    expect(conv(''), '');
    expect(conv('   \n  '), '');
    final out = conv('<div>甲</div>\n\n文本\n');
    // ignore: avoid_print
    print('--- HTML 块 ---\n$out');
    expect(out, contains('甲'));
    expect(out, contains('文本'));
  });
}
