import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/app/default_config.dart';
import 'package:mtbbs/models/managed_item.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/dialog/quick_reply_dialog.dart';

/// `assets/config/quick_replies.json` 是手工维护的配置：asset 未声明或 JSON
/// 写错都会让 [DefaultConfig.quickReplies] 静默返回空、[defaultQuickReplies]
/// 退化到内嵌兜底。这里守住"资产已声明 + JSON 合法 + 默认三条在位 + 显示/插入分离"。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('quick_replies.json 能加载，默认三条在位', () async {
    await DefaultConfig.instance.load();
    final list = DefaultConfig.instance.quickReplies;
    expect(list, isNotEmpty, reason: '为空说明 asset 未声明或 JSON 解析失败');
    for (final e in list) {
      expect(e.id, isNotEmpty);
      expect(e.name, isNotEmpty);
    }
    expect(
      list.map((e) => e.name),
      containsAll(<String>['感谢分享', '看看隐藏', '论坛有你更精彩']),
    );
  });

  test('内置常用语不含 insert（美化 BBCode 由用户自行添加）', () async {
    await DefaultConfig.instance.load();
    final thanks = DefaultConfig.instance.quickReplies.firstWhere(
      (e) => e.id == 'qr_thanks',
    );
    expect(thanks.name, '感谢分享');
    // 内置项不预设插入内容，插入内容 == 显示文本
    expect(thanks.data?['insert'], isNull);
    expect(quickReplyInsertOf(thanks), '感谢分享');

    final hidden = DefaultConfig.instance.quickReplies.firstWhere(
      (e) => e.id == 'qr_hidden',
    );
    expect(quickReplyInsertOf(hidden), hidden.name);
  });

  test('quickReplyInsertOf 优先取 data["insert"]（用户自定义美化内容）', () {
    const withInsert = ManagedItem(
      id: 'custom',
      name: '感谢分享',
      data: {'insert': '[b]感谢分享，辛苦了！[/b]'},
    );
    expect(quickReplyInsertOf(withInsert), '[b]感谢分享，辛苦了！[/b]');

    const blankInsert = ManagedItem(
      id: 'custom2',
      name: '看看隐藏',
      data: {'insert': '   '},
    );
    expect(quickReplyInsertOf(blankInsert), '看看隐藏');
  });

  test('常用语长度上限（显示 100 / 插入 500）', () {
    expect(kQuickReplyMaxLength, 100);
    expect(kQuickReplyInsertMaxLength, 500);
  });
}
