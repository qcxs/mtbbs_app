import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/pages/editor/editor_precheck.dart';

void main() {
  group('countIncompatibleEmoji', () {
    test('常规中英文 / BBCode / 空串均为 0', () {
      expect(countIncompatibleEmoji(''), 0);
      expect(countIncompatibleEmoji('你好，hello 123 [b]加粗[/b]'), 0);
      // BMP 内的符号（♪ U+266A、① U+2460）不是 4 字节字符
      expect(countIncompatibleEmoji('中文♪①'), 0);
    });

    test('统计 4 字节字符（码点 > U+FFFF）', () {
      expect(countIncompatibleEmoji('😀'), 1);
      expect(countIncompatibleEmoji('a😀b🎉c'), 2);
    });
  });

  group('stripIncompatibleEmoji', () {
    test('去掉全部 Emoji，其余原样', () {
      expect(stripIncompatibleEmoji('前😀中🎉后'), '前中后');
    });

    test('无 Emoji 时原样返回', () {
      const s = '没有 emoji 的一段话';
      expect(stripIncompatibleEmoji(s), s);
    });
  });

  group('uninsertedMedia', () {
    test('正文里已插入的不算未插入', () {
      final r = uninsertedMedia(
        content: '看图 [attachimg]11[/attachimg] 和 [attach]22[/attach]',
        imageAids: const ['11', '12'],
        attachmentAids: const ['22', '23'],
      );
      expect(r.images, {'12'});
      expect(r.attachments, {'23'});
    });

    test('正文为空时全部算未插入；空 aid 被忽略', () {
      final r = uninsertedMedia(
        content: '',
        imageAids: const ['', '5'],
        attachmentAids: const [],
      );
      expect(r.images, {'5'});
      expect(r.attachments, isEmpty);
    });

    test('全部已插入时两者皆空', () {
      final r = uninsertedMedia(
        content: '[attachimg]1[/attachimg][attach]2[/attach]',
        imageAids: const ['1'],
        attachmentAids: const ['2'],
      );
      expect(r.images, isEmpty);
      expect(r.attachments, isEmpty);
    });

    test('aid 前缀相同不会被误判（1 vs 11）', () {
      final r = uninsertedMedia(
        content: '[attachimg]11[/attachimg]',
        imageAids: const ['1'],
        attachmentAids: const [],
      );
      expect(r.images, {'1'});
    });
  });
}
