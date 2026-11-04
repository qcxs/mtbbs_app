import 'dart:async';
import 'dart:convert';

import 'package:highlight/languages/all.dart' show allLanguages;
import 'package:mtbbs/core/utils/database_helper.dart';
import 'package:mtbbs/core/utils/logger.dart';

/// 语言选择器「自动检测」的哨兵值（不是真实语法 key）
const String kAutoLanguageKey = 'auto';

/// 「纯文本」的哨兵值（语法层面用 `plaintext`）
const String kPlainLanguageKey = '';

/// 语言 key → 中文名。
///
/// 只覆盖常用项；未收录的直接显示 highlight.js 的 key（如 `smali`、`nim`）。
const Map<String, String> codeLanguageLabels = {
  'java': 'Java',
  'kotlin': 'Kotlin',
  'dart': 'Dart',
  'python': 'Python',
  'javascript': 'JavaScript',
  'typescript': 'TypeScript',
  'c': 'C',
  'cpp': 'C++',
  'csharp': 'C#',
  'go': 'Go',
  'rust': 'Rust',
  'swift': 'Swift',
  'ruby': 'Ruby',
  'php': 'PHP',
  'html': 'HTML',
  'xml': 'XML',
  'css': 'CSS',
  'sql': 'SQL',
  'bash': 'Bash',
  'shell': 'Shell',
  'json': 'JSON',
  'yaml': 'YAML',
  'markdown': 'Markdown',
  'gradle': 'Gradle',
  'groovy': 'Groovy',
  'lua': 'Lua',
  'perl': 'Perl',
  'r': 'R',
  'matlab': 'MATLAB',
  'makefile': 'Makefile',
  'dockerfile': 'Dockerfile',
  'ini': 'INI',
  'diff': 'Diff',
  'powershell': 'PowerShell',
  // MT 论坛常见
  'smali': 'Smali',
  'armasm': 'ARM 汇编',
  'x86asm': 'x86 汇编',
  'nasm': 'NASM',
  'llvm': 'LLVM IR',
  'wasm': 'WebAssembly',
  'objectivec': 'Objective-C',
  'scala': 'Scala',
  'haskell': 'Haskell',
  'erlang': 'Erlang',
  'elixir': 'Elixir',
  'clojure': 'Clojure',
  'ocaml': 'OCaml',
  'fsharp': 'F#',
  'julia': 'Julia',
  'nim': 'Nim',
  'zig': 'Zig',
  'verilog': 'Verilog',
  'vhdl': 'VHDL',
  'protobuf': 'Protocol Buffers',
  'graphql': 'GraphQL',
  'nginx': 'Nginx',
  'apache': 'Apache',
  'arduino': 'Arduino',
  'dos': '批处理',
  'vbnet': 'VB.NET',
  'vbscript': 'VBScript',
  'delphi': 'Delphi',
  'coffeescript': 'CoffeeScript',
  'elm': 'Elm',
  'toml': 'TOML',
  'properties': 'Properties',
  'django': 'Django',
  'handlebars': 'Handlebars',
  'less': 'Less',
  'scss': 'SCSS',
  'stylus': 'Stylus',
  'xquery': 'XQuery',
  'tex': 'TeX',
  'latex': 'LaTeX',
  'plaintext': '纯文本',
};

/// 全部可用语言 key（来自 highlight.js 全量注册表，按字母排序）。
///
/// `plaintext` 由「纯文本」单独表示，不进入列表。
final List<String> allCodeLanguageKeys = () {
  final keys = allLanguages.keys.where((k) => k != 'plaintext').toList()..sort();
  return List<String>.unmodifiable(keys);
}();

/// 未产生使用记录时优先展示的语言（沿用旧版列表顺序）
const List<String> commonLanguageOrder = [
  'java',
  'kotlin',
  'dart',
  'python',
  'javascript',
  'typescript',
  'c',
  'cpp',
  'csharp',
  'go',
  'rust',
  'swift',
  'ruby',
  'php',
  'html',
  'xml',
  'css',
  'sql',
  'bash',
  'json',
  'yaml',
  'markdown',
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
  'smali',
];

/// 自动检测的候选集：常用语言 + MT 常见（Smali / 汇编 / LLVM / wasm）。
///
/// 刻意**不用**全量 188 种：实测（3000 字符样本）全量打分约 214ms/次，
/// 且准确率下降（Dart→Scala、Python→isbl）；本列表约 69ms，与旧版持平，
/// 只是多认出了 smali（旧列表会误判成 gradle）。
const List<String> codeDetectionLanguageKeys = [
  ...commonLanguageOrder,
  'armasm',
  'x86asm',
  'nasm',
  'llvm',
  'wasm',
];

/// 语言显示名（未收录时回退为 key 本身）
String codeLanguageLabel(String key) {
  if (key == kPlainLanguageKey) return '纯文本';
  return codeLanguageLabels[key] ?? key;
}

/// 非主流语言的扩展名纠正（其余直接取 key）
const Map<String, String> _extensionOverrides = {
  'csharp': 'cs',
  'javascript': 'js',
  'typescript': 'ts',
  'python': 'py',
  'kotlin': 'kt',
  'rust': 'rs',
  'perl': 'pl',
  'ruby': 'rb',
  'markdown': 'md',
  'yaml': 'yml',
  'bash': 'sh',
  'shell': 'sh',
  'powershell': 'ps1',
  'objectivec': 'm',
  'matlab': 'm',
  'vbnet': 'vb',
  'vbscript': 'vbs',
  'dos': 'bat',
  'protobuf': 'proto',
  'coffeescript': 'coffee',
  'plaintext': 'txt',
};

/// 保存代码文件时的扩展名（无法识别时回退 `txt`）
String codeLanguageExtension(String key) {
  if (key == kPlainLanguageKey) return 'txt';
  final override = _extensionOverrides[key];
  if (override != null) return override;
  final cleaned = key.replaceAll(RegExp('[^a-z0-9]'), '');
  return cleaned.isEmpty ? 'txt' : cleaned;
}

/// 按「使用次数 → 常用预设 → 字母序」排序语言 key。
List<String> orderedCodeLanguageKeys(Map<String, int> usage) {
  final used = [
    for (final k in allCodeLanguageKeys)
      if ((usage[k] ?? 0) > 0) k,
  ]..sort((a, b) {
    final diff = usage[b]!.compareTo(usage[a]!);
    return diff != 0 ? diff : a.compareTo(b);
  });
  final usedSet = used.toSet();
  final preset = [
    for (final k in commonLanguageOrder)
      if (allLanguages.containsKey(k) && !usedSet.contains(k)) k,
  ];
  final presetSet = preset.toSet();
  final rest = [
    for (final k in allCodeLanguageKeys)
      if (!usedSet.contains(k) && !presetSet.contains(k)) k,
  ];
  return [...used, ...preset, ...rest];
}

/// 代码高亮的语言使用次数（用于选择器把常用语言前移）。
///
/// 不追求精确：每手动选择一次 +1，持久化在 [DatabaseHelper] 的通用元数据里。
class CodeLanguageUsage {
  CodeLanguageUsage._();
  static final CodeLanguageUsage instance = CodeLanguageUsage._();

  static const String _storageKey = 'code_highlight_language_usage';

  final Map<String, int> _counts = {};
  bool _loaded = false;

  Map<String, int> get counts => Map.unmodifiable(_counts);

  /// 从数据库加载（幂等；失败不阻断使用，只是排序退化为预设顺序）
  Future<void> loadIfNeeded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await DatabaseHelper.instance.getMeta(_storageKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          final value = entry.value;
          if (value is int && value > 0) _counts['${entry.key}'] = value;
        }
      }
    } catch (e) {
      AppLogger.w('CODE', 'load language usage failed: $e');
    }
  }

  int countOf(String key) => _counts[key] ?? 0;

  /// 记录一次手动选择并异步落盘（内存即时生效）
  void record(String key) {
    if (key.isEmpty || key == kAutoLanguageKey) return;
    _counts[key] = (_counts[key] ?? 0) + 1;
    unawaited(_persist());
  }

  Future<void> _persist() async {
    try {
      await DatabaseHelper.instance.setMeta(_storageKey, jsonEncode(_counts));
    } catch (e) {
      AppLogger.w('CODE', 'save language usage failed: $e');
    }
  }
}
