import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/app/default_config.dart';
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

  test('常用语支持"显示 / 插入"分离', () async {
    await DefaultConfig.instance.load();
    final thanks = DefaultConfig.instance.quickReplies.firstWhere(
      (e) => e.id == 'qr_thanks',
    );
    // 显示文本不变，插入内容是美化后的 BBCode
    expect(thanks.name, '感谢分享');
    expect(quickReplyInsertOf(thanks), contains('[b]'));
    // 未配置 insert 的条目，插入内容 == 显示文本
    final hidden = DefaultConfig.instance.quickReplies.firstWhere(
      (e) => e.id == 'qr_hidden',
    );
    expect(quickReplyInsertOf(hidden), hidden.name);
  });

  test('常用语长度上限（显示 100 / 插入 500）', () {
    expect(kQuickReplyMaxLength, 100);
    expect(kQuickReplyInsertMaxLength, 500);
  });
}
