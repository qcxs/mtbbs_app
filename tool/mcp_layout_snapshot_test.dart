import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/pages/settings/models/mcp_settings.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:provider/provider.dart';

/// 渲染 MCP 设置页并导出 PNG，供人眼检查布局（不是断言测试）。
///
/// 运行：`flutter test tool/mcp_layout_snapshot_test.dart`
/// 产物：`build/mcp_settings_preview.png`
final _boundaryKey = GlobalKey();

class _Harness extends StatelessWidget {
  const _Harness();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Scaffold(
      body: ListView(
        children: [for (final m in mcpSettings()) m.build(context, settings)],
      ),
    );
  }
}

void main() {
  testWidgets('导出 MCP 设置页预览图', (tester) async {
    tester.view.physicalSize = const Size(720, 1500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: SettingsProvider(),
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: RepaintBoundary(key: _boundaryKey, child: const _Harness()),
        ),
      ),
    );
    await tester.pump();

    // 展开一个分组，便于观察展开布局
    await tester.tap(find.text('只读编辑器草稿'));
    await tester.pumpAndSettle();

    final boundary =
        _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/mcp_settings_preview.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
