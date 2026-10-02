import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/utils/url_util.dart';

/// [originUrlForCdn] 的契约 —— CDN 加载失败时回退原站用的地址映射。
///
/// 只在"该地址确实属于本站点 CDN"时才给出等价原站地址，其余一律返回 null，
/// 避免把不该回退的请求（OSS 附件、未配 CDN 的站点）打到原站。
void main() {
  group('originUrlForCdn', () {
    test('CDN 无尾斜杠：前缀替换成原站', () {
      expect(
        originUrlForCdn(
          'https://cdn-bbs.mt2.cn/static/image/smiley/qq/1.gif',
          cdn: 'https://cdn-bbs.mt2.cn',
          base: 'https://bbs.binmt.cc',
        ),
        'https://bbs.binmt.cc/static/image/smiley/qq/1.gif',
      );
    });

    test('CDN 带尾斜杠：收敛双斜杠，路径不错位', () {
      // 历史配置 'https://static.52pojie.cn/' 与 '$cdn/static/…' 拼接会产生 '//'
      expect(
        originUrlForCdn(
          'https://static.52pojie.cn//static/image/smiley/qq/1.gif',
          cdn: 'https://static.52pojie.cn/',
          base: 'https://www.52pojie.cn',
        ),
        'https://www.52pojie.cn/static/image/smiley/qq/1.gif',
      );
    });

    test('base 带尾斜杠：同样收敛，不产生双斜杠', () {
      expect(
        originUrlForCdn(
          'https://cdn.x.com/a.gif',
          cdn: 'https://cdn.x.com',
          base: 'https://x.com/',
        ),
        'https://x.com/a.gif',
      );
    });

    test('未配 CDN（空串）→ null（本来就直连原站）', () {
      expect(
        originUrlForCdn('https://x.com/a.gif', cdn: '', base: 'https://x.com'),
        isNull,
      );
    });

    test('CDN 与原站相同 → null（无处可退）', () {
      expect(
        originUrlForCdn(
          'https://x.com/a.gif',
          cdn: 'https://x.com',
          base: 'https://x.com',
        ),
        isNull,
      );
    });

    test('不属于该 CDN 的地址（如 OSS 附件）→ null', () {
      expect(
        originUrlForCdn(
          'https://oss.binmt.cc/forum/202609/30/a.jpg',
          cdn: 'https://cdn-bbs.mt2.cn',
          base: 'https://bbs.binmt.cc',
        ),
        isNull,
      );
    });

    test('前缀相同但不同站点的域名不被误判（cdn.com vs cdn.com.cn）', () {
      expect(
        originUrlForCdn(
          'https://cdn.com.cn/a.gif',
          cdn: 'https://cdn.com',
          base: 'https://x.com',
        ),
        isNull,
      );
    });
  });
}
