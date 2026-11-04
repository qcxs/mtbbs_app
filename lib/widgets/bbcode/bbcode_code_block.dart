import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:highlight/highlight.dart' show highlight, Node;
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:mtbbs/config/brand_colors.dart';
import 'package:mtbbs/core/utils/clipboard_helper.dart';
import 'package:mtbbs/platform/optional/file_save.dart';
import 'package:mtbbs/widgets/bbcode/code_highlight_languages.dart';
import 'package:mtbbs/widgets/bbcode/code_language_picker_sheet.dart';
import 'package:mtbbs/widgets/common/app_sheet.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';

part 'bbcode_code_block_actions.dart';
part 'bbcode_code_block_render.dart';

/// BBCode [code] 代码块渲染组件
///
/// 由 [PostHtmlWidget] 的 `customWidgetBuilder` 按
/// `div[data-code-index]` 占位元素注入（块级）。
/// 使用 highlight 语法树 + 主题色渲染，左侧显示行号，附带一键复制按钮。
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

  String _language = '';
  bool _wordWrap = true;

  /// 自动检测时参与打分的最大字符数（避免长代码块扫描全量语言过慢）
  static const int _kDetectSampleLength = 3000;

  final ScrollController _codeController = ScrollController();
  bool _truncated = false;

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

  /// 使用 re_highlight 的 highlightAuto 自动检测语言
  ///
  /// 候选集为 [codeDetectionLanguageKeys]（常用 + Smali/汇编等），
  /// 且只取正文前 [_kDetectSampleLength] 字符参与打分——
  /// 语言特征在开头就已确定，整篇扫描只会拖慢长代码块。
  void _detectLanguage() {
    final sample = widget.code.length > _kDetectSampleLength
        ? widget.code.substring(0, _kDetectSampleLength)
        : widget.code;
    final result = _highlight.highlightAuto(sample, codeDetectionLanguageKeys);
    final detected = result.language?.toString() ?? '';
    if (mounted) {
      setState(() => _language = detected);
    }
  }

  /// 供 part 扩展使用（扩展无法直接访问受保护的 setState）
  void _setState(VoidCallback fn) {
    if (mounted) setState(fn);
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
}
