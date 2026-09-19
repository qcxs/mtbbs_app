import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/pages/editor/editor_dialogs.dart';
import 'package:mtbbs/pages/settings/widgets/dialogs.dart';
import 'package:mtbbs/widgets/bbcode/bbcode_controller.dart';

/// 设置 / 编辑器弹窗的生命周期回归。
///
/// 共同场景：弹窗提交会触发变更 → `notifyListeners()` → main.dart 的 MyApp
/// 用 `context.watch` 包住 MaterialApp，于是**整个 MaterialApp 被重建**；
/// 而此刻弹窗刚 pop、仍在退场动画中，子树会继续重建。
///
/// 控制器若在 pop 前后就 dispose（`showDialog` 的 Future 在 pop 时就完成，
/// 不是动画结束时），重建时会命中
/// 「A TextEditingController was used after being disposed」。
/// 修复方式：控制器由弹窗内容的 State 持有，随子树卸载才释放。
class _FireableNotifier extends ChangeNotifier {
  void fire() => notifyListeners();
}

/// 挂载宿主，返回「触发全局重建」的回调与宿主 context
Future<({void Function() rebuildEverything, BuildContext context})> _pumpHost(
  WidgetTester tester,
) async {
  final notifier = _FireableNotifier();
  late BuildContext hostContext;
  await tester.pumpWidget(
    AnimatedBuilder(
      animation: notifier,
      // 模拟 main.dart：通知 → 重建整个 MaterialApp
      builder: (context, _) => MaterialApp(
        home: Builder(
          builder: (ctx) {
            hostContext = ctx;
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
      ),
    ),
  );
  return (rebuildEverything: notifier.fire, context: hostContext);
}

/// 固定帧推进（输入框光标闪烁会持续排帧，不能 pumpAndSettle）
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  testWidgets('数字输入弹窗（设置项）：保存触发全局重建时不抛异常', (tester) async {
    final host = await _pumpHost(tester);

    showNumberDialog(
      context: host.context,
      title: '正文字号',
      initValue: 16,
      min: 12,
      max: 32,
      onSave: (v) async => host.rebuildEverything(),
    );
    await _settle(tester);

    await tester.enterText(find.byType(TextField), '24');
    await tester.tap(find.text('确定'));
    await _settle(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('内联输入弹窗（加粗等）：插入触发全局重建时不抛异常', (tester) async {
    final host = await _pumpHost(tester);

    showInlineInputDialog(
      host.context,
      '[b]',
      '[/b]',
      '加粗',
      '输入要加粗的文字',
      BBCodeController(),
      host.rebuildEverything, // 插入后聚焦正文 → 编辑器/预览重建
    );
    await _settle(tester);

    await tester.enterText(find.byType(TextField), '加粗内容');
    await tester.tap(find.text('确定'));
    await _settle(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('文本输入弹窗（插入链接）：提交触发全局重建时不抛异常', (tester) async {
    final host = await _pumpHost(tester);

    showTextInputDialog(
      host.context,
      title: '插入链接',
      label: 'URL',
      hint: 'https://...',
      value: '',
      secondLabel: '显示文字',
      secondHint: '可选',
      secondValue: '',
      onSubmit: (url, text) => host.rebuildEverything(),
    );
    await _settle(tester);

    await tester.enterText(find.byType(TextField).first, 'https://a.com');
    await tester.tap(find.text('确定'));
    await _settle(tester);

    expect(tester.takeException(), isNull);
  });
}
