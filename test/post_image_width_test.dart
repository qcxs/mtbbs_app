import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/widgets/bbcode/post_html_widget.dart';

/// 帖子图片宽度策略回归测试：
/// - 窄屏：默认图片占满可用宽度
/// - 宽屏：默认图片封顶 maxImageWidth（600）
/// - [img=W,H]：尊重显式宽，但 clamp 到可用宽度防溢出
/// - 未指定尺寸：只约束宽度上限，不强制宽度 → 低分辨率小图按原始像素渲染，不被放大拉糊
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

  group('BbcodeImage 实际布局宽度', () {
    Widget build({double? explicitWidth, double maxImageWidth = 600}) {
      return MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BbcodeImage(
              url: 'https://example.com/x.png',
              explicitWidth: explicitWidth,
              maxImageWidth: maxImageWidth,
            ),
          ),
        ),
      );
    }

    testWidgets('窄屏（350）：占满容器宽度', (tester) async {
      tester.view.physicalSize = const Size(350, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(build());
      // 图片占位为无限动画，不能 pumpAndSettle
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.getSize(find.byType(BbcodeImage)).width, 350);
    });

    testWidgets('宽屏（800）：封顶 600', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(build());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.getSize(find.byType(BbcodeImage)).width, 600);
    });

    testWidgets('[img=120,H] 显式宽：按 120 布局', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(build(explicitWidth: 120));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.getSize(find.byType(BbcodeImage)).width, 120);
    });

    testWidgets('未指定尺寸：不强制宽度，宽度由原始像素决定', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(build());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      // 关键回归：width 必须留空，否则低分辨率小图会被拉伸放大（变糊）。
      // 渲染器对块级自定义组件下发松约束，留空即按解码后的原始像素测量；
      // 解码链路 allowUpscaling=false，故结果天然 ≤ 原始像素宽。
      expect(image.width, isNull);
      // 上限（可用宽封顶 maxImageWidth）仍用于解码与占位，取 2 倍
      expect(image.memCacheWidth, 1200);
    });

    testWidgets('[img=120,H] 显式宽：强制该宽度（尊重作者，可放大）', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(build(explicitWidth: 120));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(image.width, 120);
    });
  });
}
