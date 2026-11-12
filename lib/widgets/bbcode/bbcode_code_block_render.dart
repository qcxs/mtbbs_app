part of 'bbcode_code_block.dart';

/// 代码行高倍数与内容内边距（与代码体的 textStyle/padding 对齐）
const double _kLineHeight = 1.5;
const double _kPadding = 12;

/// 等宽字体单字符宽度 ≈ 0.6em，用于估算行号槽宽度
const double _kCharWidthRatio = 0.6;

/// 代码体渲染 —— 语法高亮解析、行号布局、折叠与顶栏/底栏。
extension on _BbcodeCodeBlockState {
  /// 不限制行数（设置项填 0）时不做折叠/测量
  bool get _unlimited => widget.maxLines <= 0;

  /// 折叠高度 = 行数 × 行高 + 上下内边距
  double get _collapsedHeight =>
      widget.maxLines * widget.fontSize * _kLineHeight + _kPadding * 2;

  /// 把整段代码解析成语法高亮片段，再按行拆分（保留每个片段的样式）
  List<TextSpan> _highlightLines(
    Map<String, TextStyle> theme,
    TextStyle baseStyle,
  ) {
    final source = widget.code.replaceAll('\t', ' ' * 8);
    final language = _renderLanguage.isEmpty ? 'plaintext' : _renderLanguage;
    List<Node> nodes;
    try {
      nodes = highlight.parse(source, language: language).nodes ?? const [];
    } catch (_) {
      // 语言未注册等异常：退化为纯文本，至少保证代码可见
      nodes = [Node(value: source)];
    }

    final lines = <List<InlineSpan>>[[]];

    // 文本可能横跨多行，按 '\n' 拆到对应的行里
    void addText(String text, TextStyle style) {
      final parts = text.split('\n');
      for (var i = 0; i < parts.length; i++) {
        if (i > 0) lines.add(<InlineSpan>[]);
        if (parts[i].isNotEmpty) {
          lines.last.add(TextSpan(text: parts[i], style: style));
        }
      }
    }

    void walk(Node node, TextStyle style) {
      var current = style;
      final className = node.className;
      if (className != null) {
        final classStyle = theme[className];
        if (classStyle != null) current = current.merge(classStyle);
      }
      final value = node.value;
      if (value != null) addText(value, current);
      final children = node.children;
      if (children != null) {
        for (final child in children) {
          walk(child, current);
        }
      }
    }

    for (final node in nodes) {
      walk(node, baseStyle);
    }

    return [
      for (final line in lines)
        TextSpan(
          style: baseStyle,
          // 空行用零宽空格占位，保证与行号列的行高一致
          children: line.isEmpty ? const [TextSpan(text: '\u200B')] : line,
        ),
    ];
  }

  /// 构建带行号的代码体
  ///
  /// [fill] 为 true 时铺满可用宽度；false 时（无限宽测量）按内容宽度布局。
  /// [forceWrap] 用于完整代码抽屉：始终折行（抽屉只有纵向滚动）。
  Widget _buildCodeBody(
    ColorScheme cs, {
    required bool fill,
    bool forceWrap = false,
  }) {
    final isDark = cs.brightness == Brightness.dark;
    final theme = isDark ? monokaiSublimeTheme : githubTheme;
    final baseStyle = context.appTypography.mono.copyWith(
      fontSize: widget.fontSize,
      height: _kLineHeight,
      color: theme['root']?.color,
    );
    final lines = _highlightLines(theme, baseStyle);
    final wrap = forceWrap || _wordWrap;
    final digits = _lineCount.toString().length;
    // 按实际位数取宽（行号右对齐，额外 6px 作为左侧留白），避免槽过宽
    final gutterWidth = digits * widget.fontSize * _kCharWidthRatio + 6;

    final numberStyle = context.appTypography.mono.copyWith(
      fontSize: widget.fontSize,
      height: _kLineHeight,
      color: cs.codeBlockBarText.withValues(alpha: 0.55),
    );

    // 行号只用于定位，不属于代码内容：禁用选区，避免复制代码时把
    // 「1 2 3…」一起带走（否则粘贴到编辑器里还得手工删行号）。
    Widget number(int index) => SelectionContainer.disabled(
      child: SizedBox(
        width: gutterWidth,
        child: Text(
          '${index + 1}',
          textAlign: TextAlign.right,
          style: numberStyle,
        ),
      ),
    );

    Widget line(int index) => Text.rich(lines[index], softWrap: wrap);

    final background = theme['root']?.backgroundColor ?? cs.codeBlockBg;
    final padding = const EdgeInsets.symmetric(
      vertical: _kPadding,
      horizontal: _kPadding,
    );

    if (wrap || !fill) {
      // 折行（或无限宽测量）：每行一个 Row，行高随该行折行增长，
      // 行号始终与该逻辑行的首行对齐。
      return Container(
        color: background,
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < lines.length; i++)
              Row(
                mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  number(i),
                  const SizedBox(width: 6),
                  if (fill) Expanded(child: line(i)) else line(i),
                ],
              ),
          ],
        ),
      );
    }

    // 关闭自动换行：行号固定在左侧，代码整体横向滚动
    return Container(
      color: background,
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < lines.length; i++) number(i),
            ],
          ),
          const SizedBox(width: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < lines.length; i++) line(i),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// [fill] 为 true 时撑满可用宽度（常规块级场景）；false 时按内容宽度布局
  Widget _buildShell(ColorScheme cs, {required bool fill}) {
    final body = _buildCodeBody(cs, fill: fill);

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
              _setState(() => _wordWrap = !_wordWrap);
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
          // 复制按钮
          GestureDetector(
            onTap: () async {
              final ok = await ClipboardHelper.write(widget.code);
              showToast(
                ok ? '已复制' : '复制到剪切板失败',
                duration: const Duration(seconds: 1),
              );
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
          const SizedBox(width: 6),
          // 保存为文件（扩展名跟随当前高亮语言）
          GestureDetector(
            onTap: _saveCodeToFile,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: cs.codeBlockIconActive.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                Icons.save_alt,
                size: 12,
                color: cs.codeBlockBarText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
