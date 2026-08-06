import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as htmlParser;
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/parser/bbcode2html.dart';
import 'package:mtbbs/core/parser/html2bbcode.dart';
import 'package:mtbbs/core/parser/post_parser.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/bbcode/post_html_widget.dart';
import 'package:provider/provider.dart';

/// 表情渲染链路回归测试
///
/// 表情分两段式管线：
///   HTML(<img smilieid>) →parse层 Html2BBCode→ [呵呵] →渲染层 BBCode2Html→ <img>
///
/// 设计约定：表情数据由站点隔离的 [EmojiService] 维护，parse 层
/// （Html2BBCode）默认自行读取当前站点数据——为空时静默跳过表情还原
/// （"什么也不做"），不依赖调用方传递，也不依赖加载时序。
/// 测试通过显式传参注入数据以隔离站点环境。
void main() {
  setUp(() {
    SiteStore.instance.init();
  });

  // ==================== parse 层：Html2BBCode 表情还原 ====================

  group('parse 层 Html2BBCode 表情还原', () {
    const html = '<img smilieid="1240" src="https://x/smilies/1.gif" />';

    test('显式传 smilieIdMap：表情还原为 [呵呵]', () {
      final converter = Html2BBCode(smilieIdMap: const {'1240': '[呵呵]'});
      expect(converter.convert(html), '[呵呵]');
    });

    test('空 smilieIdMap：表情被静默丢弃（复现丢失 bug）', () {
      final converter = Html2BBCode(smilieIdMap: const {});
      expect(converter.convert(html), '');
    });

    test('不传时自取站点数据：站点未加载（为空）则什么也不做', () {
      // 测试环境 EmojiService 未加载 → smilieIdMap 为空 → 表情不还原
      final converter = Html2BBCode();
      expect(converter.convert(html), '');
    });
  });

  // ==================== parsePostFromTable 集成 ====================

  group('parsePostFromTable 表情集成', () {
    dom.Element buildPostTable() {
      // 真实 Discuz 模板：td.t_f 位于嵌套 table 内（div.t_fsz 下）
      return htmlParser
          .parse(
            '<table id="pid1" class="plhin"><tr>'
            '<td class="pls"><div class="pi"><div class="authi"><a href="space-uid-1.html">u</a></div></div></td>'
            '<td class="plc">'
            '<div class="pti"><div class="authi"><em id="authorposton1">2026-8-6</em></div></div>'
            '<div class="pct"><div class="pcb"><div class="t_fsz">'
            '<table cellspacing="0"><tr><td class="t_f" id="postmessage_1">'
            'hello<img smilieid="1240" src="https://x/smilies/1.gif" />world'
            '</td></tr></table>'
            '</div></div></div>'
            '</td>'
            '</tr></table>',
          )
          .querySelector('table')!;
    }

    test('生产路径不传参：站点表情未加载时静默丢弃，不报错', () {
      // parsePostFromTable 不接收 smilieIdMap，解析层自取站点数据
      final post = parsePostFromTable(buildPostTable());
      expect(post['bbcode'], 'helloworld');
    });
  });

  // ==================== 渲染层：BBCode2Html 表情替换 ====================

  group('渲染层 BBCode2Html 表情替换', () {
    test('[呵呵] + emojiMap → 表情 img', () {
      final converter = BBCode2Html(
        emojiMap: const {'[呵呵]': 'https://x/1.gif'},
      );
      final html = converter.convert('[呵呵]');
      expect(html, contains('<img src="https://x/1.gif" data-type="emoji"'));
    });

    test('emojiMap 为空：[呵呵] 原样保留且不抛异常', () {
      final converter = BBCode2Html();
      expect(converter.convert('[呵呵]'), '[呵呵]');
    });

    test('[emoji_1240] + smilieIdMap → 表情 img', () {
      final converter = BBCode2Html(
        emojiMap: const {'[呵呵]': 'https://x/1.gif'},
        smilieIdMap: const {'1240': '[呵呵]'},
      );
      final html = converter.convert('[emoji_1240]');
      expect(html, contains('data-type="emoji"'));
    });
  });

  // ==================== widget 层：PostHtmlWidget 兜底 ====================

  group('widget 层 PostHtmlWidget 表情兜底', () {
    testWidgets('表情数据未加载时：不抛异常，[呵呵] 原样显示', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider.value(
              value: SettingsProvider(),
              child: const PostHtmlWidget(bbcode: '[呵呵]'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('[呵呵]'), findsOneWidget);
    });
  });
}
