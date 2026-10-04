import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/pages/settings/models/mcp_settings.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:provider/provider.dart';

/// 复刻设置分组页的渲染方式（`SettingsGroupPage` 就是裸 ListView + 逐项 build）
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
  testWidgets('能力开关展开内容的左缩进与标题错位问题', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: SettingsProvider(),
        child: const MaterialApp(home: _Harness()),
      ),
    );
    await tester.pump();

    // 展开「只读编辑器草稿」分组
    await tester.tap(find.text('只读编辑器草稿'));
    await tester.pumpAndSettle();

    final titleX = tester.getTopLeft(find.text('只读编辑器草稿')).dx;
    final subtitleX = tester
        .getTopLeft(find.textContaining('读取编辑器里正在写的内容与历史快照'))
        .dx;
    final toolX = tester.getTopLeft(find.text('list_editor_sessions')).dx;
    final toolDescX = tester.getTopLeft(find.textContaining('列出编辑器里正在写的内容')).dx;

    // ListTile 标题/副标题：contentPadding 16 + leading 24 + gap 16 = 56
    expect(titleX, 56.0);
    expect(subtitleX, 56.0);
    // 展开面板左缘对齐标题（56），面板内边距 12 → 内容在 68
    expect(toolX, 68.0);
    // 工具名与描述同一缩进
    expect(toolDescX, toolX);

    // 再次点按折叠后，内容消失
    await tester.tap(find.text('只读编辑器草稿'));
    await tester.pumpAndSettle();
    expect(find.text('list_editor_sessions'), findsNothing);
  });
}
