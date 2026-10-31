import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:mtbbs/config/brand_colors.dart';
import 'package:mtbbs/widgets/common/app_sheet.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';

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

/// BBCode [code] 代码块渲染组件
///
/// 由 [PostHtmlWidget] 的 `customWidgetBuilder` 按
/// `div[data-code-index]` 占位元素注入（块级）。
/// 使用 flutter_highlight 提供语法高亮，附带一键复制按钮。
/// 使用 re_highlight 的 highlightAuto 检测代码语言。
class BbcodeCodeBlock extends StatefulWidget {
  final String code;
  final double fontSize;

  /// 折叠态最多显示的行数；<= 0 表示不限制（完整展开）。
  ///
  /// 默认 18 行；实际值来自设置项「代码块最大行数」，
  /// 由 [PostHtmlWidget] 注入。高度按「行数 × 行高」换算。
  final int maxLines;

  const BbcodeCodeBlock({
    super.key,
    required this.code,
    this.fontSize = 13,
    this.maxLines = 18,
  });

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

  /// 代码行高倍数与内容内边距（与 [HighlightView] 的 textStyle/padding 对齐）
  static const double _kLineHeight = 1.5;
  static const double _kPadding = 12;

  final ScrollController _codeController = ScrollController();
  bool _truncated = false;

  /// 不限制行数（设置项填 0）时不做折叠/测量
  bool get _unlimited => widget.maxLines <= 0;

  /// 折叠高度 = 行数 × 行高 + 上下内边距
  double get _collapsedHeight =>
      widget.maxLines * widget.fontSize * _kLineHeight + _kPadding * 2;

  @override
  void initState() {
    super.initState();
    _detectLanguage();
    _scheduleTruncationCheck();
  }

  @override
  void didUpdateWidget(covariant BbcodeCodeBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code) {
      _truncated = false;
      _detectLanguage();
      _scheduleTruncationCheck();
    } else if (oldWidget.maxLines != widget.maxLines) {
      // 设置项变更：按新行数重新判断是否需要折叠
      _truncated = false;
      _scheduleTruncationCheck();
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  /// 折叠态是否真的超出高度（靠不可滚动的滚动视图的 maxScrollExtent 判断，
  /// 与分享页 `_ClampedBody` 同一套做法）
  void _scheduleTruncationCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_codeController.hasClients) return;
      final truncated = _codeController.position.maxScrollExtent > 0;
      if (truncated != _truncated) setState(() => _truncated = truncated);
    });
  }

  int get _lineCount => widget.code.split('\n').length;

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

  void _showSelectableDialog() {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.code, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(_languageLabel, style: const TextStyle(fontSize: 15)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 18),
              tooltip: '复制',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: widget.code));
                showToast('已复制', duration: const Duration(seconds: 1));
              },
            ),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.6,
          ),
          decoration: BoxDecoration(
            color: cs.codeBlockBg,
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            child: SelectableText(
              widget.code,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: widget.fontSize,
                color: cs.codeTextColor,
                height: 1.5,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        // flutter_widget_from_html 为超宽表格套了横向滚动，测量单元格时会
        // 给出**无限宽**约束。此时必须退化为「内容宽度」布局（不撑满、
        // 不用 Spacer），否则 double.infinity + Spacer 会触发
        // "BoxConstraints forces an infinite width" 并中断整表渲染。
        return _buildShell(cs, fill: constraints.maxWidth.isFinite);
      },
    );
  }

  /// [fill] 为 true 时撑满可用宽度（常规块级场景）；false 时按内容宽度布局
  Widget _buildShell(ColorScheme cs, {required bool fill}) {
    final isDark = cs.brightness == Brightness.dark;
    final codeTheme = isDark ? monokaiSublimeTheme : githubTheme;
    final highlighted = HighlightView(
      widget.code,
      language: _renderLanguage,
      theme: codeTheme,
      padding: const EdgeInsets.all(_kPadding),
      textStyle: TextStyle(
        fontFamily: 'monospace',
        fontSize: widget.fontSize,
        height: _kLineHeight,
      ),
    );
    // 自动换行：直接纵向排版；关闭换行：横向滚动（长行不折断）
    final body = _wordWrap
        ? highlighted
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: highlighted,
          );

    const bottomRadius = BorderRadius.vertical(bottom: Radius.circular(6));
    // 设置项填 0 = 不限制：始终完整展开，不做测量/折叠
    final showFooter = !_unlimited && _truncated;

    return Container(
      width: fill ? double.infinity : null,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: cs.codeBlockBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: fill
            ? CrossAxisAlignment.stretch
            : CrossAxisAlignment.start,
        children: [
          _buildTopBar(cs, fill: fill),
          ClipRRect(
            borderRadius: showFooter ? BorderRadius.zero : bottomRadius,
            child: _unlimited ? body : _buildCollapsedBody(cs, body),
          ),
          if (showFooter)
            ClipRRect(
              borderRadius: bottomRadius,
              child: _buildFooter(cs, fill: fill),
            ),
        ],
      ),
    );
  }

  /// 折叠态：裁到设置的行数高度；确实超出时底部画一层渐隐，提示还有内容
  Widget _buildCollapsedBody(ColorScheme cs, Widget body) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: _collapsedHeight),
      child: Stack(
        children: [
          SingleChildScrollView(
            // 不可滚动：只为测量/裁切（与分享页 _ClampedBody 同一套做法）
            controller: _codeController,
            physics: const NeverScrollableScrollPhysics(),
            child: body,
          ),
          if (_truncated)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        cs.codeBlockBg.withValues(alpha: 0),
                        cs.codeBlockBg,
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 底部「查看全部代码」入口：打开抽屉看完整代码（与评分区的「查看全部」同位置）
  Widget _buildFooter(ColorScheme cs, {required bool fill}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _showFullCodeSheet,
        child: Container(
          width: fill ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: cs.outlineVariant, width: 0.5),
            ),
          ),
          child: Row(
            // 无限宽约束下不能用 MainAxisSize.max / Spacer
            mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Icon(Icons.unfold_more, size: 14, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                '查看全部代码',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '共 $_lineCount 行',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
              if (fill) const Spacer() else const SizedBox(width: 10),
              Icon(Icons.chevron_right, size: 16, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }

  /// 抽屉：完整代码（可纵向滚动、可复制）。
  ///
  /// 不在正文里原地展开——长代码展开后「收起」会被推到很远的下方，
  /// 用户滚不回去；抽屉可随时下滑/点关闭收起。
  void _showFullCodeSheet() {
    final cs = Theme.of(context).colorScheme;
    final codeTheme = cs.brightness == Brightness.dark
        ? monokaiSublimeTheme
        : githubTheme;
    showAppSheet(
      context: context,
      maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      builder: (ctx) => AppSheetScaffold(
        title: '代码 · $_languageLabel（$_lineCount 行）',
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 20),
            tooltip: '复制代码',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.code));
              showToast('已复制', duration: const Duration(seconds: 1));
            },
          ),
        ],
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
          child: HighlightView(
            widget.code,
            language: _renderLanguage,
            theme: codeTheme,
            padding: const EdgeInsets.all(_kPadding),
            textStyle: TextStyle(
              fontFamily: 'monospace',
              fontSize: widget.fontSize,
              height: _kLineHeight,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(ColorScheme cs, {required bool fill}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: cs.codeBlockBarBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
      ),
      child: Row(
        // 无限宽约束下不能用 MainAxisSize.max / Spacer（会要求无限宽）
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        children: [
          // 语言标签（可点击切换）
          GestureDetector(
            onTap: _showLanguagePicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: cs.codeBlockIconActive.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _languageLabel,
                    style: TextStyle(fontSize: 11, color: cs.codeBlockBarText),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 12,
                    color: cs.codeBlockBarText,
                  ),
                ],
              ),
            ),
          ),
          if (fill) const Spacer() else const SizedBox(width: 6),
          // 自动换行切换（高度/行数会变，折叠判断需重算）
          GestureDetector(
            onTap: () {
              setState(() => _wordWrap = !_wordWrap);
              _scheduleTruncationCheck();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _wordWrap
                    ? cs.codeBlockIconActive.withValues(alpha: 0.15)
                    : cs.codeBlockIconActive.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Icon(
                Icons.wrap_text,
                size: 14,
                color: _wordWrap
                    ? cs.codeBlockIconActive
                    : cs.codeBlockIconInactive,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // 文本选择按钮（弹窗可自由选择/复制）
          GestureDetector(
            onTap: _showSelectableDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: cs.codeBlockIconActive.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.text_fields, size: 12, color: cs.codeBlockBarText),
                  const SizedBox(width: 4),
                  Text(
                    '自由复制',
                    style: TextStyle(fontSize: 11, color: cs.codeBlockBarText),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          // 复制按钮
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: widget.code));
              showToast('已复制', duration: const Duration(seconds: 1));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: cs.codeBlockIconActive.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.copy_rounded,
                    size: 12,
                    color: cs.codeBlockBarText,
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
