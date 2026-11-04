part of 'bbcode_code_block.dart';

/// 语言切换、保存与完整代码抽屉。
extension on _BbcodeCodeBlockState {
  /// 实际用于渲染的语言标识（空字符串=纯文本）
  String get _renderLanguage => _language;

  /// 保存文件时使用的扩展名（无法识别时按纯文本 .txt 处理）
  String get _fileExtension => codeLanguageExtension(_renderLanguage);

  int get _lineCount => widget.code.split('\n').length;

  /// 获取当前语言的显示名称
  String get _languageLabel => codeLanguageLabel(_language);

  String _timestamp() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  /// 把原始代码另存为文件（扩展名跟随当前高亮语言）
  Future<void> _saveCodeToFile() async {
    final extension = _fileExtension;
    final fileName = 'code_${_timestamp()}.$extension';
    final outcome = await FileSave.saveText(
      widget.code,
      fileName: fileName,
      dialogTitle: '保存代码',
      allowedExtensions: [extension],
    );
    if (!mounted) return;
    switch (outcome) {
      case FileSaveOutcome.saved:
        showToast('已保存 $fileName', duration: const Duration(seconds: 2));
        break;
      case FileSaveOutcome.canceled:
        break;
      case FileSaveOutcome.unavailable:
        showToast('当前平台不支持保存文件');
        break;
      case FileSaveOutcome.failed:
        showToast('保存失败');
        break;
    }
  }

  void _showLanguagePicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => CodeLanguagePickerSheet(
        current: _language,
        onPick: (key) {
          if (key == kAutoLanguageKey) {
            _detectLanguage();
            return;
          }
          // 手动选择才计入「常用」，自动检测结果不参与排序
          CodeLanguageUsage.instance.record(key);
          _setState(() => _language = key);
        },
      ),
    );
  }

  /// 抽屉：完整代码（可纵向滚动、可选中复制）。
  ///
  /// 不在正文里原地展开——长代码展开后「收起」会被推到很远的下方，
  /// 用户滚不回去；抽屉可随时下滑/点关闭收起。
  void _showFullCodeSheet() {
    showAppSheet(
      context: context,
      maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      builder: (ctx) => AppSheetScaffold(
        title: '代码 · $_languageLabel（$_lineCount 行）',
        actions: [
          IconButton(
            icon: const Icon(Icons.save_alt, size: 20),
            tooltip: '保存为文件',
            onPressed: _saveCodeToFile,
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 20),
            tooltip: '复制代码',
            onPressed: () async {
              final ok = await ClipboardHelper.write(widget.code);
              showToast(
                ok ? '已复制' : '复制到剪切板失败',
                duration: const Duration(seconds: 1),
              );
            },
          ),
        ],
        // 抽屉是独立路由，不在正文的 SelectionArea 作用域内，
        // 必须自带一个，否则完整代码无法长按选中（正文里的截断态可以）。
        child: SelectionArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 20),
            child: _buildCodeBody(
              Theme.of(ctx).colorScheme,
              fill: true,
              forceWrap: true,
            ),
          ),
        ),
      ),
    );
  }
}
