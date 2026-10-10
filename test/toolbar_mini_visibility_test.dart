import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/config/toolbar_config.dart';
import 'package:mtbbs/core/app/default_config.dart';
import 'package:mtbbs/models/managed_item.dart';

/// 工具栏是**一套**：完整版与迷你版共用 `toolbarItems`，只在各上下文可见性上不同。
/// 这里守住"toolbar.json 的 `mini` 解析"与"隐藏时仍保留 `mini` 键"两条易错点。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('toolbar.json 的 mini 字段解析为 data["mini"]', () async {
    await DefaultConfig.instance.load();
    final items = defaultToolbarItems();
    ManagedItem byId(String id) => items.firstWhere((e) => e.id == id);

    // 帖子页 + 私信页都默认显示
    expect(toolbarMiniVisible(byId('bold'), MiniToolbarContext.thread), isTrue);
    expect(toolbarMiniVisible(byId('bold'), MiniToolbarContext.pm), isTrue);
    // 仅帖子页
    expect(
      toolbarMiniVisible(byId('quote'), MiniToolbarContext.thread),
      isTrue,
    );
    expect(toolbarMiniVisible(byId('quote'), MiniToolbarContext.pm), isFalse);
    // 未声明 mini 的项（附件）两边都不显示
    expect(
      toolbarMiniVisible(byId('attach'), MiniToolbarContext.thread),
      isFalse,
    );

    // 撤销/重做默认在两个迷你上下文都显示（迷你编辑器无固定撤销按钮，靠工具栏）
    expect(toolbarMiniVisible(byId('undo'), MiniToolbarContext.thread), isTrue);
    expect(toolbarMiniVisible(byId('redo'), MiniToolbarContext.pm), isTrue);

    // 常用语作为工具栏项存在，默认帖子页迷你显示、私信页不支持
    expect(
      toolbarMiniVisible(byId('quickReply'), MiniToolbarContext.thread),
      isTrue,
    );
    expect(
      miniToolbarSupportsItem(MiniToolbarContext.pm, 'quickReply'),
      isFalse,
    );
    expect(miniToolbarSupportsItem(MiniToolbarContext.pm, 'image'), isFalse);
  });

  test('withMiniVisible 隐藏时仍保留 mini 键（否则合并默认值无法隐藏）', () {
    const item = ManagedItem(
      id: 'bold',
      name: '加粗',
      data: {
        'mini': ['thread', 'pm'],
      },
    );
    final hidden = withMiniVisible(item, MiniToolbarContext.thread, false);
    expect(hidden.containsKey('mini'), isTrue);
    expect(hidden['mini'], ['pm']);

    final added = withMiniVisible(item, MiniToolbarContext.thread, true);
    expect((added['mini'] as List), containsAll(<String>['thread', 'pm']));
  });
}
