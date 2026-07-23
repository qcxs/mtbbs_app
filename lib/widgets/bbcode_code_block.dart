import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/languages/all.dart';

/// 常用语言列表（用于语言切换选择器）
const _languages = [
  ('plain', '纯文本'),
  ('auto', '自动检测'),
  ('java', 'Java'),
  ('kotlin', 'Kotlin'),
  ('dart', 'Dart'),
  ('python', 'Python'),
  ('javascript', 'JavaScript'),
  ('typescript', 'TypeScript'),
  ('c', 'C'),
  ('cpp', 'C++'),
  ('csharp', 'C#'),
  ('go', 'Go'),
  ('rust', 'Rust'),
  ('swift', 'Swift'),
  ('ruby', 'Ruby'),
  ('php', 'PHP'),
  ('html', 'HTML'),
  ('xml', 'XML'),
  ('css', 'CSS'),
  ('sql', 'SQL'),
  ('bash', 'Bash'),
  ('json', 'JSON'),
  ('yaml', 'YAML'),
  ('markdown', 'Markdown'),
  ('gradle', 'Gradle'),
  ('groovy', 'Groovy'),
  ('lua', 'Lua'),
  ('perl', 'Perl'),
  ('r', 'R'),
  ('matlab', 'MATLAB'),
  ('makefile', 'Makefile'),
  ('dockerfile', 'Dockerfile'),
  ('ini', 'INI'),
  ('diff', 'Diff'),
  ('powershell', 'PowerShell'),
];

/// 将 BBCode 字符串按 [code] 分割为片段
List<({bool isCode, String content})> splitByCode(String bbcode) {
  final segments = <({bool isCode, String content})>[];
  final regex = RegExp(r'\[code\]([\s\S]*?)\[/code\]', caseSensitive: false);
  int lastEnd = 0;
  for (final match in regex.allMatches(bbcode)) {
    if (match.start > lastEnd) {
      segments.add((
        isCode: false,
        content: bbcode.substring(lastEnd, match.start),
      ));
    }
    segments.add((isCode: true, content: match.group(1)!));
    lastEnd = match.end;
  }
  if (lastEnd < bbcode.length) {
    segments.add((isCode: false, content: bbcode.substring(lastEnd)));
  }
  return segments;
}

/// BBCode [code] 代码块渲染组件
///
/// 使用 flutter_highlight 提供语法高亮，附带一键复制按钮。
/// 使用 re_highlight 的 highlightAuto 检测代码语言。
class BbcodeCodeBlock extends StatefulWidget {
  final String code;
  final double fontSize;

  const BbcodeCodeBlock({super.key, required this.code, this.fontSize = 13});

  @override
  State<BbcodeCodeBlock> createState() => _BbcodeCodeBlockState();
}

class _BbcodeCodeBlockState extends State<BbcodeCodeBlock> {
  static final Highlight _highlight = Highlight()
    ..registerLanguages(builtinAllLanguages);

  static const _detectLanguages = [
    'java',
    'kotlin',
    'dart',
    'python',
    'javascript',
    'typescript',
    'cpp',
    'c',
    'csharp',
    'go',
    'rust',
    'swift',
    'php',
    'ruby',
    'html',
    'xml',
    'css',
    'sql',
    'bash',
    'json',
    'yaml',
    'gradle',
    'groovy',
    'lua',
    'perl',
    'r',
    'matlab',
    'makefile',
    'dockerfile',
    'ini',
    'diff',
    'powershell',
  ];

  String _language = '';
  bool _wordWrap = true;

  @override
  void initState() {
    super.initState();
    _detectLanguage();
  }

  /// 使用 re_highlight 的 highlightAuto 自动检测语言
  void _detectLanguage() {
    final result = _highlight.highlightAuto(widget.code, _detectLanguages);
    final detected = result.language?.toString() ?? '';
    if (mounted) {
      setState(() => _language = detected);
    }
  }

  /// 实际用于渲染的语言标识（空字符串=纯文本）
  String get _renderLanguage => _language;

  /// 获取当前语言的显示名称
  String get _languageLabel {
    if (_language.isEmpty) return '纯文本';
    for (final entry in _languages) {
      if (entry.$1 == _language) return entry.$2;
    }
    return _language;
  }

  void _showLanguagePicker() {
    showModalBottomSheet(
      context: context,
      constraints: const BoxConstraints(maxHeight: 420),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        // 当前语言排在顶部
        final sorted = List.of(_languages)
          ..sort((a, b) {
            final aMatch = a.$1 == _language ? 0 : 1;
            final bMatch = b.$1 == _language ? 0 : 1;
            final diff = aMatch.compareTo(bMatch);
            if (diff != 0) return diff;
            return a.$2.compareTo(b.$2);
          });
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: cs.outlineVariant)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.translate, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    '切换高亮语言',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(ctx).pop(),
                    child: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  for (final entry in sorted)
                    _LanguageTile(
                      label: entry.$2,
                      selected: entry.$1 == _language,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        if (entry.$1 == 'auto') {
                          _detectLanguage();
                        } else {
                          setState(() => _language = entry.$1);
                        }
                      },
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF272822),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTopBar(),
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(6),
              bottomRight: Radius.circular(6),
            ),
            child: _wordWrap
                ? SingleChildScrollView(
                    child: HighlightView(
                      widget.code,
                      language: _renderLanguage,
                      theme: monokaiSublimeTheme,
                      padding: const EdgeInsets.all(12),
                      textStyle: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: widget.fontSize,
                        height: 1.5,
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: HighlightView(
                      widget.code,
                      language: _renderLanguage,
                      theme: monokaiSublimeTheme,
                      padding: const EdgeInsets.all(12),
                      textStyle: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: widget.fontSize,
                        height: 1.5,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    // 代码块背景始终是深色，顶栏文字使用固定亮色（不跟随主题）
    const barTextColor = Color(0xFFB0B0B0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
      ),
      child: Row(
        children: [
          // 语言标签（可点击切换）
          GestureDetector(
            onTap: _showLanguagePicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _languageLabel,
                    style: TextStyle(fontSize: 11, color: barTextColor),
                  ),
                  const SizedBox(width: 3),
                  Icon(Icons.arrow_drop_down, size: 12, color: barTextColor),
                ],
              ),
            ),
          ),
          const Spacer(),
          // 自动换行切换
          GestureDetector(
            onTap: () => setState(() => _wordWrap = !_wordWrap),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _wordWrap
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Icon(
                Icons.wrap_text,
                size: 14,
                color: _wordWrap ? Colors.white : const Color(0xFF888888),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // 复制按钮
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: widget.code));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已复制'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.copy_rounded, size: 12, color: barTextColor),
                  const SizedBox(width: 4),
                  Text(
                    '复制',
                    style: TextStyle(fontSize: 11, color: barTextColor),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 语言选择列表瓦片
class _LanguageTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LanguageTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      title: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: selected ? cs.onSurfaceVariant : null,
          fontWeight: selected ? FontWeight.w600 : null,
        ),
      ),
      trailing: selected
          ? Icon(Icons.check, size: 18, color: cs.onSurfaceVariant)
          : null,
      onTap: onTap,
    );
  }
}
