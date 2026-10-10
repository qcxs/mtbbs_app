import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:mtbbs/core/app/page_helper.dart';

/// [extractPaginationFromLinks] 的行为契约 —— 从 `<a>` 链接兜底推断分页。
///
/// 关键约束：**帖子正文 / 楼层里的链接属于用户内容，不能当分页依据**。
/// 回归来源：tid=174316 单页帖子正文里引用了别的帖子（`...?tid=174230&page=2`），
/// 被误判成 2 页，进而重复拉取并显示重复评论。
void main() {
  group('分页链接兜底提取', () {
    test('正文里的 page=N 链接不得污染分页（单页帖子 → 1 页）', () {
      // 真实结构：单页帖子没有 .pg，正文里有跨帖引用链接（page=2），
      // 每个楼层还带"回复/只看该作者"按钮（page=1）。
      final doc = html_parser.parse('''
<html><body>
<div id="postlist">
  <table id="pid11934419">
    <tr>
      <td class="t_f"><a href="https://bbs.binmt.cc/forum.php?mod=viewthread&tid=174230&page=2&mobile=2">帖子</a></td>
      <td><a href="forum.php?mod=post&action=reply&fid=50&tid=174316&page=1">回复</a></td>
    </tr>
  </table>
  <table id="pid11934436">
    <tr><td class="t_f"><div class="t_fsz">正文</div></td></tr>
  </table>
</div>
</body></html>
''');
      final p = extractPaginationFromLinks(doc);
      expect(p['currentPage'], 1);
      expect(p['totalPages'], 1);
    });

    test('正文单元格（td.t_f / .t_fsz）内的链接同样排除', () {
      final doc = html_parser.parse('''
<html><body>
<table><tr><td class="t_f"><a href="/forum.php?mod=viewthread&tid=1&page=5">x</a>
<div class="t_fsz"><a href="/forum.php?mod=viewthread&tid=2&page=7">y</a></div></td></tr></table>
</body></html>
''');
      final p = extractPaginationFromLinks(doc);
      expect(p['totalPages'], 1);
    });

    test('正文外的真实分页链接仍能识别（多页帖子 → 2 页）', () {
      final doc = html_parser.parse('''
<html><body>
<div class="pgbtn"><a class="bm_h" href="thread-174230-2-1.html">下一页 »</a></div>
<div id="postlist">
  <table id="pid1"><tr><td class="t_f">hi</td></tr></table>
</div>
</body></html>
''');
      final p = extractPaginationFromLinks(doc);
      expect(p['currentPage'], 1);
      expect(p['totalPages'], 2);
    });
  });
}
