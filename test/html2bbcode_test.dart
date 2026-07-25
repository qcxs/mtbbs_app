import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/site_store.dart';
import 'package:mtbbs/core/html2bbcode.dart';

void main() {
  setUpAll(() {
    SiteStore.instance.init();
  });

  group('Html2BBCode - 表格转换', () {
    test('基础表格', () {
      const html = '<table><tr><td>单元格1</td><td>单元格2</td></tr></table>';
      final converter = Html2BBCode();
      final result = converter.convert(html);
      expect(result, '[table][tr][td]单元格1[/td][td]单元格2[/td][/tr][/table]');
    });

    test('带 <tbody> 的表格（无额外空白）', () {
      const html =
          '<table><tbody><tr>'
          '<td width="20%"><div align="center"><strong>网盘名称</strong></div></td>'
          '<td width="30%"><div align="center"><strong>官方网址</strong></div></td>'
          '</tr></tbody></table>';
      final converter = Html2BBCode();
      final result = converter.convert(html);
      expect(
        result,
        '[table][tr]'
        '[td][align=center][b]网盘名称[/b][/align][/td]'
        '[td][align=center][b]官方网址[/b][/align][/td]'
        '[/tr][/table]',
      );
    });

    test('表格中含链接', () {
      const html =
          '<table><tr>'
          '<td><a href="https://www.feejii.com/" target="_blank">https://www.feejii.com</a></td>'
          '<td>小飞机网盘</td>'
          '</tr></table>';
      final converter = Html2BBCode();
      final result = converter.convert(html);
      expect(
        result,
        '[table][tr]'
        '[td][url=https://www.feejii.com/]https://www.feejii.com[/url][/td]'
        '[td]小飞机网盘[/td]'
        '[/tr][/table]',
      );
    });

    test('多行多列表格（推荐清单）', () {
      const html =
          '<table><tbody><tr>'
          '<td><div align="center"><strong>网盘名称</strong></div></td>'
          '<td><div align="center"><strong>必须登录下载</strong></div></td>'
          '</tr><tr>'
          '<td><div align="center">小飞机网盘</div></td>'
          '<td><div align="center">❌ 否</div></td>'
          '</tr><tr>'
          '<td><div align="center">蓝奏云</div></td>'
          '<td><div align="center">❌ 否</div></td>'
          '</tr></tbody></table>';
      final converter = Html2BBCode();
      final result = converter.convert(html);
      expect(
        result,
        '[table]'
        '[tr]'
        '[td][align=center][b]网盘名称[/b][/align][/td]'
        '[td][align=center][b]必须登录下载[/b][/align][/td]'
        '[/tr]'
        '[tr]'
        '[td][align=center]小飞机网盘[/align][/td]'
        '[td][align=center]❌ 否[/align][/td]'
        '[/tr]'
        '[tr]'
        '[td][align=center]蓝奏云[/align][/td]'
        '[td][align=center]❌ 否[/align][/td]'
        '[/tr]'
        '[/table]',
      );
    });

    test('真实帖子 HTML 表格片段', () {
      // 从实际帖子 HTML 提取的表格片段（无标签间空白）
      const html =
          ''
          '<font size="4"><strong>一、论坛推荐网盘清单（附金币奖励机制）</strong></font><br>'
          '<br>'
          '<table cellspacing="0" class="t_table" style="width:98%">'
          '<tbody>'
          '<tr>'
          '<td width="20%"><div align="center"><strong>网盘名称</strong></div></td>'
          '<td width="30%"><div align="center"><strong>官方网址</strong></div></td>'
          '<td width="15%"><div align="center"><strong>必须登录下载</strong></div></td>'
          '<td width="15%"><div align="center"><strong>非会员限速</strong></div></td>'
          '<td width="20%"><div align="center"><strong>备注说明</strong></div></td>'
          '</tr>'
          '<tr>'
          '<td><div align="center">小飞机网盘</div></td>'
          '<td><a href="https://www.feejii.com/" target="_blank">https://www.feejii.com</a></td>'
          '<td><div align="center">❌ 否</div></td>'
          '<td><div align="center">❌ 全程不限速</div></td>'
          '<td>论坛签约合作网盘，用户可通过专属通道免费扩容至 1TB，支持大文件稳定传输</td>'
          '</tr>'
          '</tbody>'
          '</table>';
      final converter = Html2BBCode();
      final result = converter.convert(html);
      expect(result, contains('[size=4][b]一、论坛推荐网盘清单（附金币奖励机制）[/b][/size]'));
      expect(
        result,
        contains(
          '[table][tr]'
          '[td][align=center][b]网盘名称[/b][/align][/td]'
          '[td][align=center][b]官方网址[/b][/align][/td]'
          '[td][align=center][b]必须登录下载[/b][/align][/td]'
          '[td][align=center][b]非会员限速[/b][/align][/td]'
          '[td][align=center][b]备注说明[/b][/align][/td]'
          '[/tr]'
          '[tr]'
          '[td][align=center]小飞机网盘[/align][/td]'
          '[td][url=https://www.feejii.com/]https://www.feejii.com[/url][/td]'
          '[td][align=center]❌ 否[/align][/td]'
          '[td][align=center]❌ 全程不限速[/align][/td]'
          '[td]论坛签约合作网盘，用户可通过专属通道免费扩容至 1TB，支持大文件稳定传输[/td]'
          '[/tr][/table]',
        ),
      );
    });
  });

  group('Html2BBCode - 现有功能回归', () {
    test('加粗 strong', () {
      final result = Html2BBCode().convert('<strong>重要内容</strong>');
      expect(result, '[b]重要内容[/b]');
    });

    test('链接 a', () {
      final result = Html2BBCode().convert(
        '<a href="https://example.com" target="_blank">示例</a>',
      );
      expect(result, '[url=https://example.com]示例[/url]');
    });

    test('字体大小 font size', () {
      final result = Html2BBCode().convert('<font size="4">大号文字</font>');
      expect(result, '[size=4]大号文字[/size]');
    });

    test('字体颜色 font color', () {
      final result = Html2BBCode().convert('<font color="Red">红色文字</font>');
      expect(result, '[color=Red]红色文字[/color]');
    });

    test('居中对齐 div align', () {
      final result = Html2BBCode().convert('<div align="center">居中</div>');
      expect(result, '[align=center]居中[/align]');
    });

    test('有序列表 ul.litype_1', () {
      const html =
          '<ul type="1" class="litype_1">'
          '<li>第一项</li>'
          '<li>第二项</li>'
          '</ul>';
      final result = Html2BBCode().convert(html);
      expect(result, '[list=1]\n[*]第一项\n[*]第二项\n[/list]');
    });

    test('水平线 hr', () {
      final result = Html2BBCode().convert('前文<hr>后文');
      expect(result, '前文[hr]后文');
    });
  });

  group('Html2BBCode - 52pojie 代码块转换', () {
    test('parsedown-markdown 带 hljs 高亮的代码块', () {
      // 52pojie（https://www.52pojie.cn/）的代码块样式
      // <code data-highlighted="yes" class="hljs language-smali"> 内含 &amp; 等 HTML 实体
      const html = ''
          '<div class="parsedown-markdown">'
          '<pre>'
          '<em class="CopyMyCode" style="cursor: pointer; font-size: 12px; color: rgb(51, 102, 153) !important;"> 复制代码</em>'
          '<em class="hideCode" style="cursor: pointer; font-size: 12px; color: rgb(51, 102, 153) !important;"> 隐藏代码<br></em>'
          '<code data-highlighted="yes" class="hljs language-smali">'
          'v33 = sub_3E398(&amp;v483); \n'
          '   if ( v33 ) \n'
          '     v34 = (time(nullptr) - v33) &gt; 0x4F19FF; \n'
          '   else \n'
          '     v34 = 1; \n'
          '   v452 = v34;'
          '</code>'
          '</pre>'
          '</div>';
      final converter = Html2BBCode();
      final result = converter.convert(html);
      // 应跳过 <em> 按钮文本（复制代码/隐藏代码），只提取 <code> 内代码
      expect(result, contains('[code]'));
      expect(result, contains('[/code]'));
      expect(result, isNot(contains('复制代码')));
      expect(result, isNot(contains('隐藏代码')));
      // HTML 实体应被解码（&amp; → &, &gt; → >）
      expect(result, contains('&v483'));
      expect(result, contains('> 0x4F19FF'));
      // 代码内容应完整包含
      expect(result, contains('v33 = sub_3E398'));
      expect(result, contains('v452 = v34'));
    });

    test('parsedown-markdown 无 <code> 时回退到子节点', () {
      // 如果 parsedown-markdown 内没有 <code>，不应产生 [code]
      const html = '<div class="parsedown-markdown"><p>普通内容</p></div>';
      final result = Html2BBCode().convert(html);
      expect(result, isNot(contains('[code]')));
      expect(result, contains('普通内容'));
    });
  });

  group('Html2BBCode - 真实帖子段落转换', () {
    test('段落 + 加粗 + 字体', () {
      const html =
          '各位论坛用户：<br>'
          '<br>'
          '近期，我们集中收集并梳理了大家关于网盘使用的意见与建议，'
          '发现用户在“是否需登录下载”“非会员传输速度”等核心体验维度存在较多关切。'
          '为进一步优化资源分享效率与使用体验，现结合相关实测数据及用户反馈，'
          '正式发布论坛<strong>推荐 / 非推荐网盘清单</strong>，'
          '同步明确奖励机制与使用要求，具体内容如下：<br>'
          '<br>'
          '<font size="4"><strong>一、论坛推荐网盘清单（附金币奖励机制）</strong></font><br>';
      final result = Html2BBCode().convert(html);
      expect(result, contains('[b]推荐 / 非推荐网盘清单[/b]'));
      expect(result, contains('[size=4]'));
      expect(result, contains('一、论坛推荐网盘清单（附金币奖励机制）'));
    });
  });
}
