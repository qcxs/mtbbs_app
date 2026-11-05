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

  group('resolveContentUrl', () {
    test('相对脚本地址按页面所属站点补全', () {
      expect(
        resolveContentUrl(
          'forum.php?mod=viewthread&tid=1',
          base: 'https://b.example.com',
        ),
        'https://b.example.com/forum.php?mod=viewthread&tid=1',
      );
    });

    test('站点部署在子目录时保留子目录', () {
      expect(
        resolveContentUrl('forum.php?mod=forumdisplay&fid=2', base: 'https://b.com/bbs'),
        'https://b.com/bbs/forum.php?mod=forumdisplay&fid=2',
      );
    });

    test('站内绝对脚本路径同样补全', () {
      expect(
        resolveContentUrl('/forum.php?mod=viewthread&tid=2', base: 'https://b.example.com'),
        'https://b.example.com/forum.php?mod=viewthread&tid=2',
      );
    });

    test('绝对地址、App 深链与 App 内路径原样返回', () {
      const absolute = 'https://a.example.com/forum.php?mod=viewthread&tid=3';
      expect(resolveContentUrl(absolute, base: 'https://b.example.com'), absolute);
      expect(
        resolveContentUrl('mtbbs://thread/1', base: 'https://b.example.com'),
        'mtbbs://thread/1',
      );
      expect(
        resolveContentUrl('/thread/123', base: 'https://b.example.com'),
        '/thread/123',
      );
    });

    test('协议相对地址按页面站点协议补全', () {
      expect(
        resolveContentUrl('//cdn.example.com/a.png', base: 'https://b.example.com'),
        'https://cdn.example.com/a.png',
      );
    });

    test('base 为空时保持原文（无站点上下文不瞎拼）', () {
      expect(
        resolveContentUrl('forum.php?mod=viewthread&tid=4', base: ''),
        'forum.php?mod=viewthread&tid=4',
      );
    });
  });

  group('encodeQueryComponentForSite', () {
    test('utf-8 站点保持标准 UTF-8 百分号编码', () {
      expect(
        encodeQueryComponentForSite('公式', charset: 'utf-8'),
        '%E5%85%AC%E5%BC%8F',
      );
    });

    test('gbk 站点按 GBK 字节编码（52pojie 搜索）', () {
      expect(encodeQueryComponentForSite('公式', charset: 'gbk'), '%B9%AB%CA%BD');
    });

    test('ASCII 不转义，空格编码为 %20', () {
      expect(
        encodeQueryComponentForSite('abc 123', charset: 'gbk'),
        'abc%20123',
      );
    });

    test('空 / 未知 charset 回退 UTF-8', () {
      expect(encodeQueryComponentForSite('公式'), '%E5%85%AC%E5%BC%8F');
      expect(
        encodeQueryComponentForSite('公式', charset: 'unknown'),
        '%E5%85%AC%E5%BC%8F',
      );
    });
  });
}
