import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mtbbs/services/image_export.dart';

void main() {
  testWidgets('capturePng 把 RepaintBoundary 截成 PNG 字节', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: CaptureBoundary(
            key: key,
            child: const SizedBox(
              width: 120,
              height: 60,
              child: ColoredBox(color: Color(0xFF123456)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final bytes = await tester.runAsync<Uint8List?>(
      () => ImageExport.capturePng(key),
    );
    expect(bytes, isNotNull, reason: '截图应返回非空字节');
    expect(bytes!.length, greaterThan(8));
    // PNG 魔数
    expect(bytes.sublist(0, 4), <int>[0x89, 0x50, 0x4E, 0x47]);
  });

  testWidgets('capturePng 对未挂载的 key 返回 null（不崩溃）', (tester) async {
    final bytes = await tester.runAsync<Uint8List?>(
      () => ImageExport.capturePng(GlobalKey()),
    );
    expect(bytes, isNull);
  });

  testWidgets('capturePng 超长内容分块拼接：高度可超过单块上限 4096', (tester) async {
    // 造一个 200×2400 的边界 → 3x 后 600×7200，高度远超单张纹理上限，
    // 必须靠分块渲染 + 拼接才能得到完整长图
    tester.view.physicalSize = const Size(200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: CaptureBoundary(
          key: key,
          child: const SizedBox(
            width: 200,
            height: 2400,
            child: ColoredBox(color: Color(0xFF00AA55)),
          ),
        ),
      ),
    );
    await tester.pump();

    final bytes = await tester.runAsync<Uint8List?>(
      () => ImageExport.capturePng(key),
    );
    expect(bytes, isNotNull);
    final decoded = img.decodePng(bytes!)!;
    expect(decoded.width, 600);
    expect(decoded.height, 7200, reason: '长图应完整拼接，而非被单块上限截断');
  });
}
