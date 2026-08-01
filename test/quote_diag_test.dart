import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:mtbbs/core/parser/bbcode2html.dart';

/// 回归测试：quote 引文渲染。
///
/// 根因：`_brAfterClose`/`_brAfterOpen` 用 `'$1'` 作替换串，但 Dart 的
/// `String.replaceAll(RegExp, String)` 不展开 `$1`（与 JS 不同），
/// 导致匹配 `</blockquote><br>` 时把字面量 `$1` 插进 HTML。
/// 必须用 `replaceAllMapped((m) => m[1]!)`。
const bbcode =
    ''
    '[quote][color=#999999]柠清 发表于 2026-8-1 00:31[/color] \n'
    ' [color=#999999]换模型试试，话说是啥软件[/color][/quote] \n'
    ' 这模型还不行啊';

void main() {
  test('HTML 层：quote 内容完整、无 \$1 残留、块级边界无 <br>', () {
    final html = BBCode2Html().convert(bbcode);
    // ignore: avoid_print
    print(html);
    expect(html, isNot(contains(r'$1')));
    expect(html, contains('柠清 发表于 2026-8-1 00:31'));
    expect(html, contains('换模型试试，话说是啥软件'));
    expect(html, contains('这模型还不行啊'));
    // 引用后的换行不应残留 <br>（紧贴 </blockquote>）
    expect(html, isNot(matches(RegExp(r'</blockquote>\s*<br'))));
    expect(html, matches(RegExp(r'</blockquote>\s*这模型')));
  });

  testWidgets('渲染树：三行文本完整且顺序正确', (tester) async {
    final html = BBCode2Html().convert(bbcode);

    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Html(
              data: html,
              style: {
                'body': Style(
                  fontSize: FontSize(16),
                  margin: Margins.zero,
                  padding: HtmlPaddings.zero,
                ),
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final text = tester
        .elementList(find.byType(RichText))
        .map((e) => (e.widget as RichText).text.toPlainText())
        .join('|');
    // ignore: avoid_print
    print(text);
    expect(text, contains('柠清 发表于 2026-8-1 00:31'));
    expect(text, contains('换模型试试，话说是啥软件'));
    expect(text, contains('这模型还不行啊'));
    expect(text, isNot(contains(r'$1')));
  });
}
