import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:mtbbs/api/forum/viewthread/viewpid/parse.dart' as viewpid_parse;
import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/core/html2bbcode.dart';

/// 对比 detail 和 viewpid 两种 HTML→BBCode 路径的差异
///
/// 关键发现（通过 Chrome MCP 实际验证）：
/// - detail 路径使用 PC 模板，结构为 `#postlist > table#pid.plhin > td.plc > td.t_f`
/// - viewpid 路径（inajax）返回的也是 PC 模板，结构完全相同
/// - 两者中的引用块都是 `.quote > blockquote`
void main() {
  setUpAll(() {
    SiteConfig.init();
  });

  group('quote 块转换对比', () {
    // PC 模板（detail）的引用 HTML：.quote > blockquote
    test('PC 模板 .quote > blockquote → [quote]', () {
      const html =
          ''
          '<div class="quote"><blockquote>'
          '<font size="2"><a href="https://bbs.binmt.cc/forum.php?mod=redirect&amp;goto=findpost&amp;pid=11478446&amp;ptid=169489">'
          '<font color="#999999">青春向上 发表于 2026-7-19 14:25</font>'
          '</a></font><br>'
          '推荐把文档转换一下，更好看。<br>'
          '在线markdown转bbcode链接：<br>'
          'https://qcxs.github.io/mtbbs/mt-convert/'
          '</blockquote></div>'
          '牛啊，复制完预览太清晰了';
      final converter = Html2BBCode();
      final result = converter.convert(html);
      // PC 模板正确生成 [quote] 标签
      expect(result, contains('[quote]'));
      expect(result, contains('[/quote]'));
      expect(result, contains('青春向上 发表于 2026-7-19 14:25'));
      expect(result, contains('牛啊，复制完预览太清晰了'));
    });

    // viewpid（inajax）可能用 font+size 模拟引用，无 .quote 包裹
    test('viewpid 无 quote 包裹时需保留原文', () {
      const html =
          ''
          '<font size="2">回复</font> '
          '<font size="2"><a href="https://bbs.binmt.cc/forum.php?mod=redirect&amp;goto=findpost&amp;pid=11478446&amp;ptid=169489">'
          '<font color="#999999">青春向上 发表于 2026-7-19 14:25</font>'
          '</a></font><br>'
          '推荐把文档转换一下，更好看。<br>'
          '在线markdown转bbcode链接：<br>'
          'https://qcxs.github.io/mtbbs/mt-convert/<br>'
          '牛啊，复制完预览太清晰了';
      final converter = Html2BBCode();
      final result = converter.convert(html);
      // 没有 [quote] 标签，但内容应完整保留
      expect(result, isNot(contains('[quote]')));
      expect(result, contains('[size=2]回复[/size]'));
      expect(result, contains('青春向上 发表于 2026-7-19 14:25'));
      expect(result, contains('牛啊，复制完预览太清晰了'));
    });
  });

  group('convertElement vs convertElementContent', () {
    test('convertElement 处理 div.comiis_messages', () {
      // 模拟 div.comiis_messages 内的内容（viewpid 模板）
      final doc = html_parser.parseFragment(
        '<div class="comiis_messages">'
        '这是一段正文内容'
        '<div class="quote"><blockquote>这是引用</blockquote></div>'
        '正文继续'
        '</div>',
      );
      final div = doc.querySelector('div.comiis_messages')!;
      final converter = Html2BBCode();
      final result = converter.convertElement(div);
      // convertElement 会匹配 div 自身标签
      // div 没有 align 属性，不应输出 [div] 包裹
      // 但应正确处理子节点中的 quote
      expect(result, contains('[quote]'));
      expect(result, contains('这是引用'));
      expect(result, contains('正文继续'));
    });

    test('convertElementContent 处理 td.t_f (detail 模板)', () {
      // 模拟 td.t_f 内的内容（detail 模板），需用完整 table 结构包裹
      final doc = html_parser.parse(
        '<table><tr><td class="t_f" id="postmessage_123">'
        '这是一段正文内容'
        '<div class="quote"><blockquote>这是引用</blockquote></div>'
        '正文继续'
        '</td></tr></table>',
      );
      final td = doc.querySelector('td.t_f')!;
      final converter = Html2BBCode();
      final result = converter.convertElementContent(td);
      // convertElementContent 跳过 td 自身，只处理子节点
      // 应正确处理 quote
      expect(result, contains('[quote]'));
      expect(result, contains('这是引用'));
      expect(result, contains('正文继续'));
    });
  });

  group('viewpid 常见 HTML 片段', () {
    test('带链接和颜色的回复引用', () {
      const html =
          ''
          '<font size="2"><a href="https://bbs.binmt.cc/forum.php?mod=redirect&amp;goto=findpost&amp;pid=11478446&amp;ptid=169489">'
          '<font color="#999999">青春向上 发表于 2026-7-19 14:25</font>'
          '</a></font><br>'
          '推荐把文档转换一下，更好看。<br>';
      final converter = Html2BBCode();
      final result = converter.convert(html);
      // 应保留所有内容
      expect(result, contains('[size=2]'));
      expect(result, contains('[url='));
      expect(result, contains('[color=#999999]'));
      expect(result, contains('推荐把文档转换一下'));
    });

    test('纯文本段落', () {
      const html = '这是普通文本段落';
      final converter = Html2BBCode();
      final result = converter.convert(html);
      expect(result.trim(), '这是普通文本段落');
    });

    test('换行 br 处理', () {
      const html = '第一行<br>第二行<br><br>第四行';
      final converter = Html2BBCode();
      final result = converter.convert(html);
      expect(result, contains('第一行'));
      expect(result, contains('第二行'));
      expect(result, contains('第四行'));
    });
  });

  group('viewpid parseResponse PC 模板（Chrome MCP 验证的结构）', () {
    // 通过 Chrome MCP 实际查看 viewpid 返回的完整 HTML 模拟
    test('成功解析包含 quote 的 PC 模板', () {
      final inajaxBody =
          '<?xml version="1.0" encoding="utf-8"?>'
          '<root><![CDATA['
          '<table id="pid11478730" class="plhin" summary="pid11478730" cellspacing="0" cellpadding="0">'
          '<tr>'
          '<td class="pls" rowspan="2">'
          '<div class="pls favatar">'
          '<div class="pi">'
          '<div class="authi"><a href="https://bbs.binmt.cc/space-uid-153207.html" target="_blank">姝哕</a></div>'
          '</div>'
          '</div>'
          '</td>'
          '<td class="plc">'
          '<div class="pi">'
          '<strong><a id="postnum11478730">地下室</a></strong>'
          '<div class="pti">'
          '<div class="authi">'
          '<em id="authorposton11478730">发表于 <span>3 小时前</span></em>'
          '</div>'
          '</div>'
          '</div>'
          '<div class="pct">'
          '<div class="pcb">'
          '<div class="t_fsz">'
          '<table><tr><td class="t_f" id="postmessage_11478730">'
          '<div class="quote"><blockquote>'
          '<font size="2"><a href="https://bbs.binmt.cc/forum.php?mod=redirect&amp;goto=findpost&amp;pid=11478446&amp;ptid=169489" target="_blank">'
          '<font color="#999999">青春向上 发表于 2026-7-19 14:25</font>'
          '</a></font><br />'
          '推荐把文档转换一下，更好看。<br />'
          '在线markdown转bbcode链接：<br />'
          'https://qcxs.github.io/mtbbs/mt-convert/'
          '</blockquote></div><br />'
          '牛啊，复制完预览太清晰了'
          '</td></tr></table>'
          '</div>'
          '</div>'
          '</div>'
          '</td>'
          '</tr>'
          '</table>'
          ']]></root>';
      final result = viewpid_parse.parseResponse(inajaxBody, 200);
      expect(result['success'], true);
      expect(result['raw_type'], 'xml_cdata');
      final post = result['post'] as Map<String, dynamic>;
      expect(post['pid'], '11478730');
      expect(post['username'], '姝哕');
      expect(post['uid'], '153207');
      expect(post['bbcode'], contains('[quote]'));
      expect(post['bbcode'], contains('[/quote]'));
      expect(post['bbcode'], contains('青春向上 发表于 2026-7-19 14:25'));
      expect(post['bbcode'], contains('牛啊，复制完预览太清晰了'));
    });

    test('不包含 quote 的 PC 模板也能正确解析', () {
      final inajaxBody =
          '<?xml version="1.0" encoding="utf-8"?>'
          '<root><![CDATA['
          '<table id="pid12345" class="plhin">'
          '<tr>'
          '<td class="pls">'
          '<div class="pi"><div class="authi"><a href="https://bbs.binmt.cc/space-uid-999.html" target="_blank">测试用户</a></div></div>'
          '</td>'
          '<td class="plc">'
          '<div class="pct"><div class="pcb"><div class="t_fsz">'
          '<table><tr><td class="t_f" id="postmessage_12345">'
          '这是一段普通回复内容，没有引用。'
          '</td></tr></table>'
          '</div></div></div>'
          '</td>'
          '</tr>'
          '</table>'
          ']]></root>';
      final result = viewpid_parse.parseResponse(inajaxBody, 200);
      expect(result['success'], true);
      expect(result['raw_type'], 'xml_cdata');
      final post = result['post'] as Map<String, dynamic>;
      expect(post['pid'], '12345');
      expect(post['username'], '测试用户');
      expect(post['uid'], '999');
      expect(post['bbcode'], '这是一段普通回复内容，没有引用。');
      expect(post['bbcode'], isNot(contains('[quote]')));
    });
  });
}
