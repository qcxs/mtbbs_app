import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/parser/xml_helper.dart';

/// [parseSubmitResponse] 的契约 —— 发帖/回复成功响应里 tid/pid 的提取。
///
/// tid/pid 不一定出现在 `redirect` 的查询串里：伪静态站点（如 MT 论坛）回的是
/// `thread-{tid}-1-1.html`（无 `tid=`），字段可能只在 `succeedhandle_` 第 3 参 JS 对象里。
/// 这里锁定"多来源链式提取"的行为（见 docs/07 #95、docs/12）。
void main() {
  group('parseSubmitResponse · succeedhandle_ tid/pid 提取', () {
    test('MT 论坛：伪静态 redirect + 第 3 参对象 → 取到 tid/pid', () {
      const body = '<?xml version="1.0" encoding="utf-8"?>\n'
          '<root><![CDATA[<script type="text/javascript" reload="1">'
          "if(typeof succeedhandle_=='function') {succeedhandle_('thread-174520-1-1.html', "
          "'非常感谢，您的主题已发布，现在将转入主题页，请稍候……[ 点击这里转入主题列表 ]', "
          "{'fid':'42','tid':'174520','pid':'11947117','coverimg':'','sechash':''});}"
          '</script>]]></root>';
      final r = parseSubmitResponse(body);
      expect(r.success, isTrue);
      expect(r.tid, '174520');
      expect(r.pid, '11947117');
      expect(r.needsApproval, isFalse);
    });

    test('查询串站点：forum.php?mod=viewthread&tid= → 取到 tid', () {
      const body =
          "<root><![CDATA[<script>succeedhandle_("
          "'forum.php?mod=viewthread&tid=123&extra=page%3D1', '操作成功');"
          '</script>]]></root>';
      final r = parseSubmitResponse(body);
      expect(r.success, isTrue);
      expect(r.tid, '123');
    });

    test('纯伪静态路径（无查询串、无第 3 参）→ 从 thread-{tid} 取 tid', () {
      const body =
          "<root><![CDATA[<script>succeedhandle_('thread-123-1-1.html', '操作成功');"
          '</script>]]></root>';
      final r = parseSubmitResponse(body);
      expect(r.tid, '123');
    });

    test('findpost 回复跳转：ptid/pid → 取到 tid 与 pid', () {
      const body =
          "<root><![CDATA[<script>succeedhandle_("
          "'forum.php?mod=redirect&goto=findpost&ptid=19&pid=61', '回复成功');"
          '</script>]]></root>';
      final r = parseSubmitResponse(body);
      expect(r.tid, '19');
      expect(r.pid, '61');
    });

    test('第 3 参对象只带 pid、URL 只带 tid：两字段各自独立取值', () {
      const body =
          "<root><![CDATA[<script>succeedhandle_('thread-321-1-1.html', '操作成功', "
          "{'pid':'888'});</script>]]></root>";
      final r = parseSubmitResponse(body);
      expect(r.tid, '321');
      expect(r.pid, '888');
    });

    test('审核文案 → needsApproval，且仍提取伪静态 tid', () {
      const body =
          "<root><![CDATA[<script>succeedhandle_('thread-1-1-1.html', '您的帖子需要审核');"
          '</script>]]></root>';
      final r = parseSubmitResponse(body);
      expect(r.needsApproval, isTrue);
      expect(r.tid, '1');
    });
  });
}
