import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:mtbbs/core/parser/bbcode2html.dart';

/// 回归测试：图片后紧跟 [code] 块时不应出现空白。
///
/// 根因：[/appdata] 后的换行变成 `<br>`，但 block-adjacency 清理发生在
/// [code] 占位符还原之前（清理时还是 \x00CODE0\x00，不是 <pre>），
/// 导致 `<br>` 幸存并紧贴还原后的块级元素，渲染成图片下方空行。
const bbcode =
    ''
    '[appdata]{"type":"image_attach","url":"https://attach.52pojie.cn/forum/202607/31/155713n4p54574poyws4op.jpg","width":"1080","aid":"2868499","name":"Snipaste_2026-07-31_15-51-46.jpg","size":"169.75 KB","downloads":"0","uploadTime":"2026-7-31 15:57"}[/appdata] \n'
    ' [code]index.html[/code]';

void main() {
  test('图片后紧跟 [code]：<br> 不得残留在图片与 <pre> 之间', () {
    final html = BBCode2Html().convert(bbcode);
    // ignore: avoid_print
    print(html);
    // 图片后直接是 <pre>，中间不允许有 <br>
    expect(html, matches(RegExp(r'<img[^>]*/>\s*<pre')));
    expect(html, isNot(matches(RegExp(r'<img[^>]*/>\s*<br>\s*<pre'))));
    // code 块内部的代码行尾换行 <li>...<br></li> 必须保留
    expect(html, contains('index.html<br></li>'));
  });

  testWidgets('渲染树：图片与 code 块之间无空白段落', (tester) async {
    final html = BBCode2Html(emitCodePlaceholder: true).convert(bbcode);

    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HtmlWidget(
              html,
              buildAsync: false,
              textStyle: const TextStyle(fontSize: 16),
              customWidgetBuilder: (e) {
                if (e.localName == 'img') {
                  return Container(
                    key: const ValueKey('diag-img'),
                    height: 100,
                    color: Colors.blueGrey,
                  );
                }
                if (e.attributes.containsKey('data-code-index')) {
                  return Container(
                    key: const ValueKey('diag-code'),
                    height: 40,
                    color: Colors.black12,
                    child: Text(e.outerHtml),
                  );
                }
                return null;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 图片与 code 块都渲染出来
    expect(find.byKey(const ValueKey('diag-img')), findsOneWidget);
    expect(find.byKey(const ValueKey('diag-code')), findsOneWidget);

    // 关键回归：不存在「只含空白/换行」的可见段落 —— 即图片与 code 之间没有空行
    final blanks = <String>[];
    for (final el in find.byType(RichText).evaluate()) {
      final rich = el.widget as RichText;
      final ro = el.renderObject as RenderParagraph?;
      final plain = rich.text.toPlainText();
      if (plain.trim().isEmpty && (ro?.size.height ?? 0) > 0) {
        blanks.add('${ro?.size} "$plain"');
      }
      // 图片后紧跟换行的旧症状（"￼\n"）不应再出现
      expect(plain.contains('￼\n'), isFalse);
    }
    // ignore: avoid_print
    print('空白段落: $blanks');
    expect(blanks, isEmpty, reason: '图片与 code 之间不应有空行');
  });
}
