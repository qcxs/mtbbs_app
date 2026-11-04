import 'package:flutter_test/flutter_test.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:mtbbs/widgets/bbcode/code_highlight_languages.dart';

/// 代码块高亮语言目录（bbcode_code_block 的语言选择器 / 自动检测依赖它）
void main() {
  group('高亮语言目录', () {
    test('全量语言来自 highlight.js 注册表（含 MT 常见的 smali / 汇编）', () {
      expect(allCodeLanguageKeys.length, greaterThan(150));
      expect(allCodeLanguageKeys, containsAll(['smali', 'armasm', 'x86asm']));
      // 纯文本由独立哨兵表示，不进列表
      expect(allCodeLanguageKeys, isNot(contains('plaintext')));
    });

    test('保存文件扩展名映射（历史 key 不能回退成 txt）', () {
      expect(codeLanguageExtension(kPlainLanguageKey), 'txt');
      expect(codeLanguageExtension('smali'), 'smali');
      expect(codeLanguageExtension('python'), 'py');
      expect(codeLanguageExtension('csharp'), 'cs');
      expect(codeLanguageExtension('rust'), 'rs');
      expect(codeLanguageExtension('perl'), 'pl');
      expect(codeLanguageExtension('objectivec'), 'm');
      expect(codeLanguageExtension('gradle'), 'gradle');
    });

    test('选择器排序：使用记录优先，其次常用预设，最后字母序', () {
      final ordered = orderedCodeLanguageKeys({'smali': 3, 'rust': 1});
      expect(ordered.first, 'smali');
      expect(ordered[1], 'rust');
      expect(ordered[2], 'java');
      expect(ordered.length, allCodeLanguageKeys.length);
      expect(ordered.toSet().length, ordered.length); // 无重复
    });

    test('自动检测候选集能识别 smali（旧候选集会误判成 gradle）', () {
      final hl = Highlight()..registerLanguages(builtinAllLanguages);
      const code = '''
.class public Lcom/example/MainActivity;
.super Landroid/app/Activity;

.method public onCreate(Landroid/os/Bundle;)V
    .locals 2
    invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
    const-string v0, "hello"
    return-void
.end method
''';
      expect(
        hl.highlightAuto(code, codeDetectionLanguageKeys).language,
        'smali',
      );
    });
  });
}
