import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as htmlParser;
import 'package:mtbbs/api/forum/viewthread/detail/parse.dart' as detail;
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/parser/html2bbcode.dart';
import 'package:mtbbs/core/parser/html2markdown.dart';
import 'package:mtbbs/core/parser/post_parser.dart';

/// 52pojie Markdown 插件（Parsedown）HTML → Markdown / BBCode 单测
///
/// 真实结构取自 52pojie 演示帖（thread-717627）：服务端 Parsedown 输出
/// `<div class="parsedown-markdown">` + 隐藏的 `-end_FLAG_…` 结束标记，
/// 页面里没有 Markdown 原文。
void main() {
  String md(String html) =>
      htmlToMarkdown(htmlParser.parse(html).body!.querySelector('div')!);

  group('Html2Markdown - 结构还原', () {
    test('标题 / 段落 / 行内样式', () {
      final out = md(
        '<div class="parsedown-markdown">'
        '<h2>标题</h2>'
        '<p>正文 <strong>粗</strong> <em>斜</em> <code>a_b</code></p>'
        '</div>',
      );
      expect(out, contains('## 标题'));
      expect(out, contains('**粗**'));
      expect(out, contains('*斜*'));
      expect(out, contains('`a_b`'));
    });

    test('代码块：跳过按钮、扁平化 hljs span、保留语言与空行', () {
      final out = md(
        '<div class="parsedown-markdown">'
        '<pre>'
        '<em class="CopyMyCode"> 复制代码</em>'
        '<em class="hideCode"> 隐藏代码<br></em>'
        '<code class="hljs language-dart">'
        '<span class="hljs-keyword">void</span> main() {\n\n  print(1);\n}'
        '</code>'
        '</pre>'
        '</div>',
      );
      expect(out, contains('```dart'));
      expect(out, contains('void main() {\n\n  print(1);\n}'));
      expect(out, isNot(contains('复制代码')));
      expect(out, isNot(contains('隐藏代码')));
      expect(out, isNot(contains('hljs-keyword')));
    });

    test('嵌套引用累积 > 前缀', () {
      final out = md(
        '<div class="parsedown-markdown">'
        '<blockquote><p>外层</p><blockquote><p>内层</p></blockquote></blockquote>'
        '</div>',
      );
      expect(out, contains('> 外层'));
      expect(out, contains('> > 内层'));
    });

    test('无序/有序/嵌套列表', () {
      final out = md(
        '<div class="parsedown-markdown">'
        '<ul><li>甲<ul><li>乙</li></ul></li></ul>'
        '<ol><li>一</li><li>二</li></ol>'
        '</div>',
      );
      expect(out, contains('- 甲'));
      expect(out, contains('    - 乙'));
      expect(out, contains('1. 一'));
      expect(out, contains('2. 二'));
    });

    test('表格（thead/th）', () {
      final out = md(
        '<div class="parsedown-markdown">'
        '<table><thead><tr><th>A</th><th>B</th></tr></thead>'
        '<tbody><tr><td>1</td><td>2</td></tr></tbody></table>'
        '</div>',
      );
      expect(out, contains('| A | B |'));
      expect(out, contains('| --- | --- |'));
      expect(out, contains('| 1 | 2 |'));
    });

    test('附件图片转 Markdown 图片，元数据浮层跳过', () {
      final out = md(
        '<div class="parsedown-markdown">'
        '<p><ignore_js_op>'
        '<img aid="1" src="https://attach.example.com/a.png" '
        'file="https://attach.example.com/a.png" class="zoom">'
        '</ignore_js_op></p>'
        '<div class="tip tip_4 aimg_tip"><strong>1.png</strong></div>'
        '</div>',
      );
      expect(out, contains('![](https://attach.example.com/a.png)'));
      expect(out, isNot(contains('1.png')));
    });

    test('正文里的 Markdown 特殊字符被转义，不会被二次解析', () {
      final out = md(
        '<div class="parsedown-markdown"><p>a *b* [c] _d_ &lt;e&gt;</p></div>',
      );
      expect(out, contains(r'a \*b\* \[c\] \_d\_ \<e\>'));
    });

    test('容器级行内流（无 <p> 包裹）：行内 code 与正文同段', () {
      // 52pojie 真实结构（thread-2056733）：文字、<code>、<br> 直接挂在
      // div.parsedown-markdown 下。行内流必须攒成一段，不能把 code 当独立块。
      final out = md(
        '<div class="parsedown-markdown">'
        '<p>前文</p>'
        '<br>'
        '可以通过搜索 <code>call r8</code> 对应的字节码。<br>'
        '</div>',
      );
      expect(out, contains('可以通过搜索 `call r8` 对应的字节码。'));
    });

    test('列表项开头的短横不会被误判为引用/列表（正文转义）', () {
      final out = md(
        '<div class="parsedown-markdown"><p>- 不是列表</p><p># 不是标题</p></div>',
      );
      expect(out, contains(r'\- 不是列表'));
      expect(out, contains(r'\# 不是标题'));
    });
  });

  group('Html2BBCode - 52pojie Markdown 插件端到端', () {
    String conv(String html) => Html2BBCode().convert(html);

    test('标题按阅读层级放大', () {
      final out = conv(
        '<div class="parsedown-markdown">'
        '<h2>一级</h2><h3>二级</h3><h4>三级</h4>'
        '</div>',
      );
      expect(out, contains('[size=5][b]一级[/b][/size]'));
      expect(out, contains('[size=4][b]二级[/b][/size]'));
      expect(out, contains('[size=4][b]三级[/b][/size]'));
    });

    test('引用嵌套折叠为单层 [quote]，不残留字面标签', () {
      final out = conv(
        '<div class="parsedown-markdown">'
        '<blockquote><p>外层</p><blockquote><p>内层</p></blockquote></blockquote>'
        '</div>',
      );
      expect('[quote]'.allMatches(out).length, 1);
      expect('[/quote]'.allMatches(out).length, 1);
      expect(out, contains('外层'));
      expect(out, contains('内层'));
    });

    test('表格 th 转 td，不产生渲染层不认识的 [th]', () {
      final out = conv(
        '<div class="parsedown-markdown">'
        '<table><thead><tr><th>A</th></tr></thead>'
        '<tbody><tr><td>1</td></tr></tbody></table>'
        '</div>',
      );
      expect(out, contains('[table]'));
      expect(out, contains('[td]A[/td]'));
      expect(out, contains('[td]1[/td]'));
      expect(out, isNot(contains('[th]')));
    });

    test('分割线不会触发 Front Matter（不产生 [free]）', () {
      final out = conv(
        '<div class="parsedown-markdown">'
        '<p>前文</p><hr><p>后文</p><hr><p>结尾</p>'
        '</div>',
      );
      expect('[hr]'.allMatches(out).length, 2);
      expect(out, isNot(contains('[free]')));
      expect(out, contains('前文'));
      expect(out, contains('结尾'));
    });

    test('代码块保留空行，跳过复制按钮', () {
      final out = conv(
        '<div class="parsedown-markdown">'
        '<pre><em class="CopyMyCode"> 复制代码</em>'
        '<code class="hljs language-dart">line1\n\nline2</code></pre>'
        '</div>',
      );
      expect(out, contains('[code]line1\n\nline2[/code]'));
      expect(out, isNot(contains('复制代码')));
    });

    test('容器级行内 code 渲染后不换行（端到端）', () {
      final out = conv(
        '<div class="parsedown-markdown">'
        '可以通过搜索 <code>call r8</code> 对应的字节码。'
        '</div>',
      );
      expect(
        out,
        contains(
          '可以通过搜索 '
          '[color=#333333][backcolor=#f4f4f4]call r8[/backcolor][/color] '
          '对应的字节码。',
        ),
      );
    });

    test('结束标记 div 不输出内容', () {
      final out = conv(
        '<div class="parsedown-markdown-end_FLAG_ZXSQ" style="display:none">'
        '</div>',
      );
      expect(out, '');
    });

    test('非 Markdown 站点不受影响：h1/p 仍按纯文本', () {
      final out = conv('<h2>标题</h2><p>段落</p>');
      expect(out, isNot(contains('[size=')));
      expect(out, contains('标题'));
      expect(out, contains('段落'));
    });
  });

  group('parsePostFromTable - 帖内标题', () {
    /// 真实 52pojie 帖子结构：td.t_f 位于 td.plc > div.pcb > div.t_fsz 内
    dom.Element buildTable(String body, {String head = ''}) => htmlParser
        .parse(
          '<table id="pid1" class="plhin"><tr>'
          '<td class="pls"></td>'
          '<td class="plc">'
          '<div class="pct"><div class="pcb">'
          '$head'
          '<div class="t_fsz"><table><tr>'
          '<td class="t_f" id="postmessage_1">$body</td>'
          '</tr></table></div>'
          '</div></div>'
          '</td>'
          '</tr></table>',
        )
        .querySelector('table')!;

    test('Markdown 帖正文里的 h2 不会被当成帖内标题重复输出', () {
      // thread-2123217：正文首个 h2 就是帖子标题
      final post = parsePostFromTable(
        buildTable(
          '<div class="parsedown-markdown">'
          '<h2>快手 VMP 分析与还原</h2>'
          '<p>正文</p>'
          '</div>'
          '<div class="parsedown-markdown-end_FLAG_ZXSQ"></div>',
        ),
      );
      final bbcode = post['bbcode'] as String;
      expect(RegExp('快手 VMP 分析与还原').allMatches(bbcode).length, 1);
      expect(bbcode, contains('[size=5][b]快手 VMP 分析与还原[/b][/size]'));
      expect(bbcode.trimLeft(), startsWith('[size=5]'));
    });

    test('正文区之外的 h2 仍作为帖内标题前置', () {
      final post = parsePostFromTable(
        buildTable('正文', head: '<h2>帖内标题</h2>'),
      );
      expect(post['bbcode'], startsWith('[b]帖内标题[/b]\n正文'));
    });
  });

  group('parsePostFromTable - 分类信息（threadtype，招聘帖）', () {
    /// 真实结构：完整分类信息在 div.pcb > div.typeoption（td.t_f 之外），
    /// t_f 里只有补充说明。
    dom.Element buildPost() => htmlParser
        .parse(
          '<div id="postlist">'
          '<table id="pid55145978" class="plhin"><tr>'
          '<td class="pls"></td>'
          '<td class="plc"><div class="pct"><div class="pcb">'
          '<div class="typeoption">'
          '<table summary="分类信息" class="cgtl mbm">'
          '<caption>招聘</caption><tbody>'
          '<tr><th>公司名称:</th><td>360 </td></tr>'
          '<tr><th>职位名称:</th><td>高级Web安全研究员</td></tr>'
          '<tr><th>职位描述:</th><td>【要求】<br>1、挖洞<br>2、审计</td></tr>'
          '<tr><th>性别要求:</th><td>&nbsp;</td></tr>'
          '</tbody></table>'
          '</div>'
          '<div class="t_fsz"><table><tr>'
          '<td class="t_f" id="postmessage_55145978">简历请注明来自吾爱</td>'
          '</tr></table></div>'
          '</div></div></td>'
          '</tr></table>'
          '</div>',
        )
        .querySelector('table#pid55145978')!;

    test('typeoption 前置到正文，标签/值成两列表格，空值项不占行', () {
      final post = parsePostFromTable(buildPost());
      final bbcode = post['bbcode'] as String;
      expect(bbcode, startsWith('[b]招聘[/b]\n[table]'));
      expect(bbcode, contains('[tr][td]公司名称:[/td][td]360[/td][/tr]'));
      expect(
        bbcode,
        contains('[tr][td]职位描述:[/td][td]【要求】\n1、挖洞\n2、审计[/td][/tr]'),
      );
      expect(bbcode, isNot(contains('性别要求')));
      // t_f 里的补充说明排在分类信息之后
      expect(bbcode.indexOf('简历请注明来自吾爱'), greaterThan(bbcode.indexOf('[table]')));
    });
  });

  group('帖子详情 - tid 提取', () {
    test('分类信息版块：sortid=48 不会被误当成 tid', () {
      // 真实页面（thread-2103384）首个 a[href*=tid=] 是建帖链接
      // `...&sortid=48`，未锚定的 `tid=(\d+)` 会把 tid 解析成 48。
      const html =
          '<html><body>'
          '<a href="forum.php?mod=post&action=newthread&fid=39&sortid=48">招聘</a>'
          '<a href="forum.php?mod=redirect&goto=nextoldset&tid=2103384">下一主题</a>'
          '<div id="postlist"><table id="pid1" class="plhin"><tr>'
          '<td class="pls"></td><td class="plc"><div class="pct"><div class="pcb">'
          '<div class="t_fsz"><table><tr>'
          '<td class="t_f" id="postmessage_1">正文</td>'
          '</tr></table></div></div></div></td></tr></table></div>'
          '</body></html>';
      final result = detail.parseResponse(html, 200);
      expect(result['success'], true);
      expect(result['tid'], '2103384');
    });
  });

  group('parsePostFromTable - 评分记录（52pojie 与克米模板差异）', () {
    setUpAll(() => SiteStore.instance.init());

    dom.Element buildPost(String rateHtml) => htmlParser
        .parse(
          '<table id="pid1" class="plhin"><tr>'
          '<td class="pls"></td>'
          '<td class="plc"><div class="pct"><div class="pcb">'
          '<div class="t_fsz"><table><tr>'
          '<td class="t_f" id="postmessage_1">正文</td>'
          '</tr></table></div>'
          '$rateHtml'
          '</div></div></td>'
          '</tr></table>',
        )
        .querySelector('table')!;

    test('52pojie：用户链接无 a.xg1、uid 走 mod=space&uid=，仍能识别', () {
      // 真实结构：首个 <a> 是头像（文本为空），第二个才是昵称；
      // p.ratc 是「查看全部评分」操作链接，不能当汇总文案。
      final post = parsePostFromTable(
        buildPost(
          '<dl class="rate" id="ratelog_1"><dd><table class="ratl">'
          '<tbody><tr>'
          '<th class="xw1"><a href="forum.php?mod=misc&action=viewratings&tid=1&pid=1">'
          '参与人数 <span class="xi1">15</span></a></th>'
          '<th class="xw1">吾爱币 <i><span class="xi1">+16</span></i></th>'
          '<th class="xw1">热心值 <i><span class="xi1">+14</span></i></th>'
          '<th><a href="javascript:;">收起</a><i class="txt_h">理由</i></th>'
          '</tr></tbody>'
          '<tbody class="ratl_l"><tr id="rate_1_2">'
          '<td><a href="home.php?mod=space&uid=2415459"><img src="avatar.gif"></a>'
          '<a href="home.php?mod=space&uid=2415459">jhdgff</a></td>'
          '<td class="xi1"> + 2</td><td class="xi1"> + 1</td>'
          '<td class="xg1">谢谢@Thanks！</td>'
          '</tr></tbody>'
          '</table><p class="ratc">'
          '<a href="forum.php?mod=misc&action=viewratings&tid=1&pid=1">查看全部评分</a>'
          '</p></dd></dl>',
        ),
      );
      final rating = post['rating'] as Map<String, dynamic>;
      expect(rating['totalScore'], '参与人数 15');
      expect(rating['columns'], ['吾爱币 +16', '热心值 +14']);
      final entries = (rating['entries'] as List).cast<Map<String, dynamic>>();
      expect(entries, hasLength(1));
      expect(entries.first['username'], 'jhdgff');
      expect(entries.first['uid'], '2415459');
      expect(entries.first['scores'], ['+ 2', '+ 1']);
      expect(entries.first['reason'], '谢谢@Thanks！');
    });

    test('克米模板：a.xg1 + space-uid- 保持原行为', () {
      final post = parsePostFromTable(
        buildPost(
          '<dl class="rate" id="ratelog_2"><dd><table class="ratl">'
          '<tbody class="ratl_l"><tr>'
          '<th><a href="forum.php?mod=misc&action=viewratings&tid=2&pid=2">评分</a></th>'
          '<th>金币</th><th>理由</th>'
          '</tr></tbody>'
          '<tbody class="ratl_l"><tr id="rate_2_3">'
          '<td><a class="xg1" href="home.php?mod=space-uid-123">李四</a></td>'
          '<td class="xi1"> +5</td><td class="xg1">感谢分享</td>'
          '</tr></tbody>'
          '</table><p class="ratc"> +5 金币</p></dd></dl>',
        ),
      );
      final rating = post['rating'] as Map<String, dynamic>;
      expect(rating['totalScore'], '+5 金币');
      final entries = (rating['entries'] as List).cast<Map<String, dynamic>>();
      expect(entries, hasLength(1));
      expect(entries.first['uid'], '123');
      expect(entries.first['scores'], ['+5']);
    });
  });
}
