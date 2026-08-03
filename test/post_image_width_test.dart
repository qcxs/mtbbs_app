import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:mtbbs/widgets/bbcode/post_html_widget.dart';

/// 帖子图片宽度策略回归测试：
/// - 窄屏：默认图片占满可用宽度
/// - 宽屏：默认图片封顶 maxImageWidth（600）
/// - [img=W,H]：尊重显式宽，但 clamp 到可用宽度防溢出
void main() {
  group('resolvePostImageWidth 公式', () {
    test('窄屏无显式宽：占满可用宽度', () {
      expect(
        resolvePostImageWidth(availableWidth: 350, maxImageWidth: 600),
        350,
      );
    });

    test('宽屏无显式宽：封顶 maxImageWidth', () {
      expect(
        resolvePostImageWidth(availableWidth: 800, maxImageWidth: 600),
        600,
      );
    });

    test('[img=W,H] 显式宽：尊重作者意图', () {
      expect(
        resolvePostImageWidth(
          explicitWidth: 120,
          availableWidth: 800,
          maxImageWidth: 600,
        ),
        120,
      );
    });

    test('显式宽超可用宽：clamp 防溢出', () {
      expect(
        resolvePostImageWidth(
          explicitWidth: 2000,
          availableWidth: 350,
          maxImageWidth: 600,
        ),
        350,
      );
    });

    test('自定义封顶值生效', () {
      expect(
        resolvePostImageWidth(availableWidth: 800, maxImageWidth: 500),
        500,
      );
    });
  });

  Widget _build({
    required double screenWidth,
    required Key key,
    required double maxImageWidth,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Html(
            data:
                '<img src="https://example.com/x.png" style="max-width:100%;" />',
            style: {
              'body': Style(
                margin: Margins.zero,
                padding: HtmlPaddings.zero,
              ),
            },
            extensions: [
              // 与 post_html_widget ImageExtension 一致的布局逻辑
              ImageExtension(
                builder: (ctx) => LayoutBuilder(
                  builder: (context, constraints) {
                    final available = constraints.maxWidth.isFinite
                        ? constraints.maxWidth
                        : MediaQuery.sizeOf(context).width;
                    final width = resolvePostImageWidth(
                      explicitWidth:
                          double.tryParse(ctx.attributes['width'] ?? ''),
                      availableWidth: available,
                      maxImageWidth: maxImageWidth,
                    );
                    return Container(
                      key: key,
                      width: width,
                      height: 100,
                      color: Colors.blueGrey,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('flutter_html 扩展内约束=容器宽度：窄屏占满', (tester) async {
    tester.view.physicalSize = const Size(350, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const key = Key('img');
    await tester.pumpWidget(_build(screenWidth: 350, key: key, maxImageWidth: 600));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(key)).width, 350);
  });

  testWidgets('flutter_html 扩展内约束=容器宽度：宽屏封顶 600', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const key = Key('img');
    await tester.pumpWidget(_build(screenWidth: 800, key: key, maxImageWidth: 600));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(key)).width, 600);
  });
}
