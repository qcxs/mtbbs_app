import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/widgets/bbcode/bbcode_controller.dart';
import 'package:mtbbs/widgets/dialog/image_picker_sheet.dart';

/// 宽屏图片侧栏（embedded）行为回归：
/// - 插入后不关闭面板（底部抽屉才 pop）
/// - 关闭按钮走 onClose
void main() {
  late BBCodeController controller;

  setUp(() => controller = BBCodeController());
  tearDown(() => controller.dispose());

  Widget build({
    required bool embedded,
    VoidCallback? onClose,
    void Function(String aid)? onInsert,
    double width = 300,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          height: 600,
          child: ImagePickerSheet(
            embedded: embedded,
            images: const [
              {
                'aid': '1',
                'src': 'https://example.com/x.png',
                'title': '',
                'type': 'uploaded',
              },
            ],
            loading: false,
            ignoredAids: const {},
            contentText: '',
            controller: controller,
            onUpload: () async {},
            onDelete: (_) async {},
            onIgnore: (_) {},
            onRefresh: () {},
            onInsert: onInsert ?? (_) {},
            onClose: onClose,
          ),
        ),
      ),
    );
  }

  testWidgets('嵌入模式：插入后保持面板，关闭按钮走回调', (tester) async {
    var inserted = '';
    var closed = 0;
    await tester.pumpWidget(
      build(
        embedded: true,
        onInsert: (aid) => inserted = aid,
        onClose: () => closed++,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('#1'));
    await tester.pump();
    await tester.tap(find.text('插入'));
    await tester.pump();

    expect(inserted, '1');
    // 面板没有被 pop 掉
    expect(find.byType(ImagePickerSheet), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(closed, 1);
  });

  testWidgets('嵌入模式最窄 240 不溢出', (tester) async {
    await tester.pumpWidget(build(embedded: true, width: 240));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.text('图片管理'), findsOneWidget);
  });

  testWidgets('底部抽屉模式：不显示侧栏的连续插入提示', (tester) async {
    await tester.pumpWidget(build(embedded: false));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('插入后不关闭，可连续插入'), findsNothing);
    // 拖拽手柄存在（侧栏模式没有）
    expect(find.byType(ImagePickerSheet), findsOneWidget);
  });
}
