import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/config/toolbar_config.dart';
import 'package:mtbbs/core/app/default_config.dart';
import 'package:mtbbs/models/managed_item.dart';
import 'package:mtbbs/providers/settings_provider.dart';

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

    // 留言板（wall）：撤销/加粗/表情/MT图床默认显示；论坛图片不支持
    expect(toolbarMiniVisible(byId('undo'), MiniToolbarContext.wall), isTrue);
    expect(toolbarMiniVisible(byId('bold'), MiniToolbarContext.wall), isTrue);
    expect(
      toolbarMiniVisible(byId('mtImage'), MiniToolbarContext.wall),
      isTrue,
    );
    expect(toolbarMiniVisible(byId('image'), MiniToolbarContext.wall), isFalse);
    expect(miniToolbarSupportsItem(MiniToolbarContext.wall, 'image'), isFalse);
  });

  test('syncToolbarWithDefaults 给老配置补上新增上下文，且不覆盖用户已删的上下文', () async {
    await DefaultConfig.instance.load();
    final canonical = defaultToolbarItems();

    // 模拟"老配置"：所有项的 mini 都不含新增的 wall
    List<ManagedItem> stripWall(List<ManagedItem> items) => items.map((e) {
      final m = e.data?['mini'];
      if (m is List) {
        return e.copyWith(
          data: {
            ...?e.data,
            'mini': m
                .map((x) => x.toString())
                .where((x) => x != 'wall')
                .toList(),
          },
        );
      }
      return e;
    }).toList();

    final synced = syncToolbarWithDefaults(stripWall(canonical), canonical);
    ManagedItem byId(String id) => synced.firstWhere((e) => e.id == id);
    // 新增的 wall 被补进默认含它的项
    expect(
      (byId('undo').data!['mini'] as List).map((x) => x.toString()),
      contains('wall'),
    );
    // 默认不含 wall 的项不被误加
    expect(
      (byId('quote').data!['mini'] as List).map((x) => x.toString()),
      isNot(contains('wall')),
    );
    // 用户主动删掉的上下文（link 去掉 thread，但 thread 在别处仍在）不被补回
    final edited = canonical.map((e) {
      if (e.id == 'link') {
        return e.copyWith(
          data: {
            ...?e.data,
            'mini': ['pm'],
          },
        );
      }
      return e;
    }).toList();
    final synced2 = syncToolbarWithDefaults(stripWall(edited), canonical);
    final link = synced2.firstWhere((e) => e.id == 'link');
    final linkMini = (link.data!['mini'] as List).map((x) => x.toString());
    expect(linkMini, isNot(contains('thread')));
    expect(linkMini, contains('wall'));
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
