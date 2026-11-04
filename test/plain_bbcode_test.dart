import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/parser/plain_bbcode.dart';

void main() {
  group('toPlainBbcode - appdata 降级', () {
    test('图片附件 → [img]', () {
      final out = toPlainBbcode(
        r'[appdata]{"type":"image_attach","url":"https://cdn.example.com/a.png","aid":"1","name":"a.png"}[/appdata]',
      );
      expect(out, '[img]https://cdn.example.com/a.png[/img]');
    });

    test('文件附件 → [url=…]文件名[/url]', () {
      final out = toPlainBbcode(
        r'[appdata]{"type":"attach","url":"https://cdn.example.com/tool.zip","name":"tool.zip","size":"1.2MB","downloads":"3"}[/appdata]',
      );
      expect(out, '[url=https://cdn.example.com/tool.zip]tool.zip[/url]');
    });

    test('文件附件缺 url 时只留文件名', () {
      final out = toPlainBbcode(
        r'[appdata]{"type":"attach","url":"","name":"tool[1].zip"}[/appdata]',
      );
      expect(out, 'tool［1］.zip');
    });

    test(r'公式 → $…$ / $$…$$', () {
      final out = toPlainBbcode(
        r'块级 [appdata]{"type":"math","tex":"\\frac{a}{b}","display":true}[/appdata] '
        r'行内 [appdata]{"type":"math","tex":"x_{0}","display":false}[/appdata]',
      );
      expect(out, contains(r'$$\frac{a}{b}$$'));
      expect(out, contains(r'$x_{0}$'));
    });

    test('页面装饰（奖励/悬赏/投票/状态/锁定）整段丢弃', () {
      final out = toPlainBbcode(
        '[appdata]{"type":"reward","amount":"30","unit":"金币"}[/appdata]'
        '[appdata]{"type":"bounty","amount":"25","unit":"吾爱币"}[/appdata]'
        '[appdata]{"type":"poll","pollType":"单选","options":["A","B"]}'
        '[/appdata]'
        '[appdata]{"type":"pstatus","message":"本帖最后由 xx 编辑"}[/appdata]'
        '[appdata]{"type":"locked","message":"回复可见"}[/appdata]'
        '正文',
      );
      expect(out, '正文');
    });

    test('损坏 / 未知 appdata 丢弃，普通 BBCode 原样保留', () {
      final out = toPlainBbcode(
        '[b]标题[/b]\n'
        '[appdata]not-json[/appdata]\n'
        '[appdata]{"type":"unknown"[/appdata]\n'
        '[img]https://cdn.example.com/b.png[/img]',
      );
      expect(out, contains('[b]标题[/b]'));
      expect(out, contains('[img]https://cdn.example.com/b.png[/img]'));
      expect(out, isNot(contains('appdata')));
      expect(out, isNot(contains('not-json')));
    });

    test('无 appdata 时仅 trim 首尾空白', () {
      expect(toPlainBbcode('\n\n[b]hi[/b]\n\n'), '[b]hi[/b]');
    });
  });
}
