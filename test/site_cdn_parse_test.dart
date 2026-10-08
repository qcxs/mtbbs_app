import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/api/site/cdn/parse.dart';

/// 站点 CDN 解析契约 —— 从页面内联的 `STATICURL` 得到 `scheme://host`。
///
/// 该值最终喂给 `SiteStore.cdnUrl`，被拼成 `{cdn}/static/image/smiley/…`，
/// 所以解析结果必须**只到主机名**、且非绝对地址时一律返回 null（由调用方回退）。
void main() {
  group('parseCdn', () {
    test('单引号 STATICURL → scheme://host', () {
      const html =
          "<script>var STYLEID = '4', STATICURL = 'https://cdn.binmt.cc/static/', "
          "IMGDIR = 'https://cdn.binmt.cc/template/img';</script>";
      expect(parseCdn(html), 'https://cdn.binmt.cc');
    });

    test('双引号 STATICURL 同样可解析', () {
      const html = '<script>STATICURL = "https://static.52pojie.cn/static/";</script>';
      expect(parseCdn(html), 'https://static.52pojie.cn');
    });

    test('协议相对 // 补成 https', () {
      const html = "<script>STATICURL = '//cdn.x.com/static/';</script>";
      expect(parseCdn(html), 'https://cdn.x.com');
    });

    test('保留显式端口', () {
      const html = "<script>STATICURL = 'https://cdn.x.com:8443/static/';</script>";
      expect(parseCdn(html), 'https://cdn.x.com:8443');
    });

    test('相对值（站点未配置 staticurl 时的 static/）→ null', () {
      const html = "<script>STATICURL = 'static/';</script>";
      expect(parseCdn(html), isNull);
    });

    test('页面没有 STATICURL → null', () {
      expect(parseCdn('<html><body>拦截页</body></html>'), isNull);
      expect(parseCdn(''), isNull);
    });
  });

  group('parseResponse', () {
    test('非 200 → success:false', () {
      expect(parseResponse('', 403)['success'], false);
    });

    test('200 且含 STATICURL → success + cdn', () {
      const html = "<script>STATICURL = 'https://cdn.binmt.cc/static/';</script>";
      final result = parseResponse(html, 200);
      expect(result['success'], true);
      expect(result['cdn'], 'https://cdn.binmt.cc');
    });

    test('200 但不含 STATICURL → success:false', () {
      expect(parseResponse('<html></html>', 200)['success'], false);
    });
  });
}
