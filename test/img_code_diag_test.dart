import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:mtbbs/core/parser/bbcode2html.dart';

/// 回归测试：图片后紧跟 [code] 块时不应出现空白。
///
/// 根因：[/appdata] 后的换行变成 `<br>`，但 block-adjacency 清理发生在
/// [code] 占位符还原之前（清理时还是 \x00CODE0\x00，不是 <pre>），
/// 导致 `<br>` 幸存并紧贴还原后的 <pre>，渲染成图片下方空行。
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

  testWidgets('渲染树：图片与 code 块同一段落且中间无换行', (tester) async {
    final html = BBCode2Html().convert(bbcode);

    tester.view.physicalSize = const Size(800, 2000);
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
              extensions: [
                ImageExtension(
                  builder: (ctx) => Container(
                    width: double.tryParse(ctx.attributes['width'] ?? ''),
                    height: 100,
                    color: Colors.blueGrey,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 任何段落都不允许"图片后紧跟换行"（修复前是 "￼\n￼"）
    final texts = tester
        .elementList(find.byType(RichText))
        .map((e) => (e.widget as RichText).text.toPlainText());
    expect(texts.where((t) => t.contains('￼\n')), isEmpty);
    // 图片与 code 块应位于同一段落（内联相接）
    expect(texts.any((t) => t.contains('￼￼')), isTrue);
  });
}
