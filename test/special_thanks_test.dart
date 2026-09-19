import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/models/special_thanks.dart';

/// `assets/config/thanks.json` 是手工维护的配置，字段写错/漏逗号都会让
/// [SpecialThanks.load] 静默返回空列表（关于页只是少一块，不报错）。
/// 这里守住"资产已声明 + JSON 合法 + 关键字段在位"。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('thanks.json 能加载，字段齐全', () async {
    final list = await SpecialThanks.load();
    expect(list, isNotEmpty, reason: '为空说明 asset 未声明或 JSON 解析失败');

    for (final e in list) {
      expect(e.username, isNotEmpty);
      expect(e.uid, isNotEmpty);
      expect(e.title, isNotEmpty);
      expect(e.url, startsWith('http'));
      expect(e.note, isNotEmpty);
    }

    expect(list[0].uid, '139510');
    expect(list[1].uid, '51423');
  });
}
