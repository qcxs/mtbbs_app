import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/app/page_helper.dart';

/// [looksLikeInterstitialPage] 的行为契约 —— 通用拦截页（人机验证 / 防火墙）。
///
/// 判据刻意不认任何厂商特征，只判断"这是不是一个能用的论坛页"：
/// 真实 Discuz 页面必有 `<body>` 且带论坛骨架痕迹。
void main() {
  group('通用拦截页检测', () {
    test('无 body 的脚本桩（阿里云 WAF 形态）→ 命中', () {
      // 实测样本：4321 字节、`<html><script>var arg1='<40位hex>'`、无 body
      const body =
          "<html><script>var arg1='C4CC95B37E463F56C1823DFE80C0B211EBA9787A';"
          '(function(a,c){var G=a0j,d=a();while(!![]){}})(a0i,0x760bf);'
          '</script></html>';
      expect(
        looksLikeInterstitialPage(body, 'text/html; charset=utf-8'),
        isTrue,
      );
    });

    test('真实论坛页（有 body + Discuz 骨架）→ 不命中', () {
      const body =
          '<html><head><meta name="generator" content="Discuz! X3.4">'
          '</head><body><div id="ct">'
          '<input name="formhash" value="abc">'
          '</div></body></html>';
      expect(looksLikeInterstitialPage(body, 'text/html'), isFalse);
    });

    test('极小但合法的论坛页（只有骨架 id）→ 不命中', () {
      const body =
          '<html><body><div id="thread_subject">标题</div></body></html>';
      expect(looksLikeInterstitialPage(body, 'text/html'), isFalse);
    });

    test('JSON 接口响应 → 不参与判定', () {
      expect(looksLikeInterstitialPage('{"uid":0}', 'application/json'), isFalse);
    });

    test('非 text/html 或缺 <html>（如 inajax 片段）→ 不参与判定', () {
      expect(
        looksLikeInterstitialPage('<root><![CDATA[x]]></root>', 'text/xml'),
        isFalse,
      );
      expect(
        looksLikeInterstitialPage('<script>location.href=1</script>', 'text/html'),
        isFalse,
      );
    });

    test('超出体积上限 → 不判定（避免误伤大页面）', () {
      final body = '<html><script>${'x' * (65 * 1024)}</script></html>';
      expect(looksLikeInterstitialPage(body, 'text/html'), isFalse);
    });
  });
}
