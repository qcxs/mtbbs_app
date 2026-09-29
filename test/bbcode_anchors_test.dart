import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/parser/bbcode_anchors.dart';
import 'package:mtbbs/core/parser/bbcode_blocks.dart';
import 'package:mtbbs/core/parser/bbcode_source_lines.dart';

/// 锚点表 —— 编辑区与预览区之间唯一的"结构身份"来源。
///
/// 这里锁住三条不能破的约定：
/// 1. **无损**：`anchors.map((a) => a.raw).join() == 原文`，首尾相接
/// 2. **行内标签不影响锚点**：`[b]`/`[color]`… 都在切片内部
/// 3. **序号即对应关系**，且 `line` 单调不减（渲染顺序 = 文档顺序）
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 覆盖各种结构：纯段落、块级标签、图片、空行、未闭合标签…
  const sources = <String>[
    '',
    '\n\n\n',
    '只有一行文字',
    '第一段\n\n第二段\n\n第三段',
    '连续三行\n没有空行\n也是一段',
    '[quote]引用\n第二行[/quote]\n普通文字\n[code]代码[/code]',
    '[b]搜索[/b]\n支持uid、tid、username\n[b]积分分析[/b]\n利用已有信息反推积分',
    '文字[img]https://a.com/1.png[/img]文字2',
    '开头\n[hr]\n[hr]\n结尾',
    '[list]\n[*]甲\n[*]乙\n[/list]\n\n[table]\n[tr][td]甲[/td][/tr]\n[/table]',
    '[hide]隐藏[/hide]\n[free]免费[/free]\n[align=center]居中[/align]',
    '未闭合 [quote]引用\n[img]没有闭标签',
    '[url=https://a.com][img]https://a.com/x.png[/img][/url]',
  ];

  group('无损不变量', () {
    test('切完拼起来 == 原文，且首尾相接', () {
      for (final src in sources) {
        final anchors = bbAnchors(src);
        expect(
          anchors.map((a) => a.raw).join(),
          src,
          reason: '切分丢字/多字：${src.replaceAll('\n', '⏎')}',
        );
        for (var i = 0; i < anchors.length; i++) {
          expect(anchors[i].index, i, reason: '序号必须等于下标');
          if (i > 0) {
            expect(
              anchors[i].start,
              anchors[i - 1].end,
              reason: '锚点之间有缝隙或重叠：$i',
            );
          }
        }
        if (anchors.isNotEmpty) {
          expect(anchors.first.start, 0);
          expect(anchors.last.end, src.length);
        }
      }
    });

    test('空串没有锚点；整篇空白退化成一个锚点', () {
      expect(bbAnchors(''), isEmpty);
      expect(bbAnchors('\n\n\n').length, 1);
    });

    test('line 单调不减（渲染顺序 = 文档顺序）', () {
      for (final src in sources) {
        final anchors = bbAnchors(src);
        for (var i = 1; i < anchors.length; i++) {
          expect(
            anchors[i].line,
            greaterThanOrEqualTo(anchors[i - 1].line),
            reason: '锚点行号倒退',
          );
        }
      }
    });
  });

  group('切分粒度', () {
    test('空行分段', () {
      const src = '第一段\n还是第一段\n\n第二段\n\n第三段';
      final a = bbAnchors(src);
      expect(a.length, 3);
      expect(a.map((e) => e.start).toList(), [0, 11, 16]);
      expect(a.map((e) => e.kind).toSet(), {BbBlockKind.text});
    });

    test('顶层块标签各自成锚点', () {
      const src = '[quote]引用\n第二行[/quote]\n普通文字\n[code]代码[/code]';
      final a = bbAnchors(src);
      expect(a.map((e) => e.kind).toList(), [
        BbBlockKind.quote,
        BbBlockKind.text,
        BbBlockKind.code,
      ]);
      // 引用块内的换行不拆锚点（粒度只到顶层块）
      expect(a[0].raw, '[quote]引用\n第二行[/quote]');
      // 文本锚点的"行"取内容首字所在行，不是切片起点（切片以 \n 开头）
      expect(a[1].raw, '\n普通文字\n');
      expect(a[1].line, 2);
    });

    test('整行加粗标题也算一段（论坛最常见的小节写法）', () {
      const src =
          '[b]搜索[/b]\n'
          '支持uid、tid、username\n'
          '[b]积分分析[/b]\n'
          '利用已有信息反推积分\n'
          '[b]内置浏览器[/b]';
      final a = bbAnchors(src);
      expect(a.length, 3);
      expect(a.map((e) => e.line).toList(), [0, 2, 4]);
      expect(a.map((e) => e.label).toList(), ['搜索', '积分分析', '内置浏览器']);
    });

    test('加粗只包住句首时不当作标题', () {
      const src = '[b]注意[/b]这里只是句首加粗，整行不是标题\n第二行';
      expect(bbAnchors(src).length, 1);
    });

    test('行内标签不产生锚点边界', () {
      const src = 'A[b]粗[/b]B[color=red]红[/color]C';
      final a = bbAnchors(src);
      expect(a.length, 1);
      expect(a.first.raw, src);
    });
  });

  group('类型与提示', () {
    test('图片/分隔线等没有文字 → 用类型名当提示', () {
      const src = '文字\n[img]https://a.com/1.png[/img]\n文字2';
      final a = bbAnchors(src);
      expect(a.map((e) => e.kind).toList(), [
        BbBlockKind.text,
        BbBlockKind.image,
        BbBlockKind.text,
      ]);
      expect(a[1].label, '图片');
      expect(a[1].raw, '[img]https://a.com/1.png[/img]');
      expect(a[2].label, '文字2');
    });

    test('提示过长截断到 16 字', () {
      const src = '一二三四五六七八九十一二三四五六七八九十';
      expect(bbAnchors(src).first.label, '一二三四五六七八九十一二三四五六…');
    });

    test('纯空白锚点并入相邻锚点（不单独成一个渲染单元）', () {
      const src = '开头\n[hr]\n[hr]\n结尾';
      final a = bbAnchors(src);
      // 两个 [hr] 之间只有一个换行，它会并进前一个 hr，而不是自成一块
      expect(a.map((e) => e.raw).toList(), ['开头\n', '[hr]\n', '[hr]', '\n结尾']);
      for (final e in a) {
        expect(e.raw.trim(), isNotEmpty);
      }
    });
  });

  group('光标 → 锚点', () {
    test('落在哪个区间就是哪个锚点', () {
      const src = '第一段\n\n第二段\n\n第三段';
      final a = bbAnchors(src);
      expect(bbAnchorIndexAt(a, 0), 0);
      expect(bbAnchorIndexAt(a, 3), 0); // 第一段的换行仍属第一段
      expect(bbAnchorIndexAt(a, a[1].start), 1);
      expect(bbAnchorIndexAt(a, a[2].start), 2);
      expect(bbAnchorIndexAt(a, src.length), 2); // 末尾
    });

    test('段内任意位置都是同一个锚点（标记不会因光标抖动而晃）', () {
      final a = bbAnchors('第一段\n\n第二段');
      final start = a[1].start;
      for (var off = start; off <= start + 3; off++) {
        expect(bbAnchorIndexAt(a, off), 1);
      }
    });

    test('越界与空表安全', () {
      expect(bbAnchorIndexAt(const [], 5), -1);
      expect(bbAnchorIndexAt(bbAnchors('文字'), -3), -1);
    });
  });

  group('源码行切分（编辑区用）', () {
    test('按换行切行，末尾无换行也算一行', () {
      final lines = bbcodeSourceLines('甲\n乙\n');
      expect(lines.length, 3);
      expect(lines[0], (start: 0, text: '甲'));
      expect(lines[1], (start: 2, text: '乙'));
      expect(lines[2], (start: 4, text: ''));
    });

    test('空串也是「一行」', () {
      expect(bbcodeSourceLines(''), [(start: 0, text: '')]);
    });

    test('偏移 → 行号', () {
      const src = '甲\n乙\n丙';
      expect(bbcodeLineIndexOf(src, 0), 0);
      expect(bbcodeLineIndexOf(src, 1), 0); // 行尾换行符仍属本行
      expect(bbcodeLineIndexOf(src, 2), 1);
      expect(bbcodeLineIndexOf(src, 4), 2);
      expect(bbcodeLineIndexOf(src, 999), 2, reason: '越界钳到末行');
      expect(bbcodeLineIndexOf(src, -5), 0, reason: '负偏移钳到首行');
    });
  });

  group('行可见文本', () {
    test('去掉标签只留文字', () {
      expect(bbcodeLineVisibleText('[b]加粗[/b]普通'), '加粗普通');
      expect(bbcodeLineVisibleText('[color=red]红[/color]'), '红');
      expect(bbcodeLineVisibleText('[quote]引用一行'), '引用一行');
    });

    test('渲染成非文本的标签整段删掉', () {
      expect(bbcodeLineVisibleText('前[img]https://a.com/x.png[/img]后'), '前后');
      expect(bbcodeLineVisibleText('[attachimg]123[/attachimg]'), '');
      expect(bbcodeLineVisibleText('文字[attach]456[/attach]'), '文字');
      expect(bbcodeLineVisibleText('[hr]'), '');
    });

    test('空行 / 纯图片行得到空串（调用方据此退回类型名）', () {
      expect(bbcodeLineVisibleText(''), '');
      expect(bbcodeLineVisibleText('   '), '');
    });
  });
}
