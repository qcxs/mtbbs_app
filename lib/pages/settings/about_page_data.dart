part of 'about_page.dart';

/// 数据管理 —— 设置 / Cookie 的导出与导入。
extension on _AboutPageState {
  Future<void> _exportSettings() async {
    try {
      final json = await DataPortability.exportSettingsJson();
      if (!mounted) return;
      await _exportText(json, 'mtbbs_settings');
    } catch (e) {
      if (mounted) showToast('导出设置失败：$e');
    }
  }

  Future<void> _importSettings() async {
    final text = await _readImportText(label: '设置');
    if (text == null || !mounted) return;
    final confirmed = await showConfirmDialog(
      context,
      title: '导入设置',
      message: '将覆盖当前应用设置与各站点设置；缓存、账号与 Cookie 不受影响。是否继续？',
      confirmText: '导入',
      danger: true,
    );
    if (confirmed != true || !mounted) return;
    try {
      final count = await DataPortability.importSettingsJson(text);
      final settings = context.read<SettingsProvider>();
      await settings.load();
      settings.applyRuntimeConfig();
      if (mounted) showToast('已导入设置（$count 个站点）');
    } catch (e) {
      if (mounted) showToast('导入设置失败：$e');
    }
  }

  Future<void> _exportCookies() async {
    try {
      final json = await DataPortability.exportCookiesJson();
      if (!mounted) return;
      await _exportText(json, 'mtbbs_cookies');
    } catch (e) {
      if (mounted) showToast('导出 Cookie 失败：$e');
    }
  }

  Future<void> _importCookies() async {
    final text = await _readImportText(label: 'Cookie');
    if (text == null || !mounted) return;
    final confirmed = await showConfirmDialog(
      context,
      title: '导入账号 Cookie',
      message: '将覆盖各站点账号的 Cookie 与账号列表。导入后登录态可能立即变化，是否继续？',
      confirmText: '导入',
      danger: true,
    );
    if (confirmed != true || !mounted) return;
    try {
      final result = await DataPortability.importCookiesJson(text);
      for (final host in result.hosts) {
        await SessionRegistry.instance.onAccountsChanged(host);
      }
      if (!mounted) return;
      if (result.hosts.contains(SiteStore.instance.host)) {
        await context.read<AuthProvider>().onSiteChanged();
      }
      if (mounted) {
        showToast('已导入 ${result.hosts.length} 个站点、${result.jars} 份 Cookie');
      }
    } catch (e) {
      if (mounted) showToast('导入 Cookie 失败：$e');
    }
  }

  Future<String?> _readImportText({required String label}) async {
    final mode = await _pickTransferMode(exporting: false, title: '导入方式');
    if (mode == null || !mounted) return null;
    if (mode == 'clipboard') {
      final text = await ClipboardHelper.read();
      if (text != null && text.trim().isNotEmpty) return text;
      if (!mounted) return null;
      // 降级：读取失败或剪切板为空时，让用户手动粘贴，而不是只弹一条提示后
      // 要求退出流程重新复制（读取失败本身在 ClipboardHelper 内已留痕）。
      return showTextInputDialog(
        context,
        title: '从剪切板导入$label',
        message: '未能读取剪切板内容（为空或不可用），可在下方手动粘贴。',
        hintText: '在此粘贴$label JSON…',
        monospace: true,
      );
    }
    final file = await FilePick.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (file == null) return null;
    final path = file.path;
    try {
      return utf8.decode(await file.readAsBytes());
    } catch (e) {
      if (mounted) showToast('读取文件失败：$e');
      return null;
    } finally {
      // 清理 file_picker 复制到缓存的导入副本（Android/iOS）
      await FilePick.cleanupTemp(path);
    }
  }

  Future<void> _exportText(String text, String prefix) async {
    final mode = await _pickTransferMode(exporting: true, title: '导出方式');
    if (mode == null || !mounted) return;
    if (mode == 'clipboard') {
      final ok = await ClipboardHelper.write(text);
      if (mounted) {
        showToast(ok ? '已复制到剪切板' : '复制到剪切板失败');
      }
      return;
    }
    final fileName = '${prefix}_${_timestamp()}.json';
    final outcome = await FileSave.saveText(
      text,
      fileName: fileName,
    );
    if (!mounted) return;
    switch (outcome) {
      case FileSaveOutcome.saved:
        showToast('已保存');
        break;
      case FileSaveOutcome.canceled:
        break;
      case FileSaveOutcome.unavailable:
        // 平台没有「另存为」：退回应用导出目录，至少让文件落地
        final dir = await AppPaths.exportsDir;
        await Directory(dir).create(recursive: true);
        final path = p.join(dir, fileName);
        await File(path).writeAsString(text);
        if (mounted) showToast('已保存到 $path');
        break;
      case FileSaveOutcome.failed:
        showToast('保存失败');
        break;
    }
  }

  Future<String?> _pickTransferMode({
    required bool exporting,
    required String title,
  }) => showSelectDialog<String>(
    context: context,
    title: title,
    options: [
      SelectOption(
        value: 'clipboard',
        icon: exporting ? Icons.copy_all_outlined : Icons.content_paste,
        label: exporting ? '复制到剪切板' : '从剪切板导入',
      ),
      SelectOption(
        value: 'file',
        icon: exporting ? Icons.save_alt : Icons.folder_open,
        label: exporting ? '保存为文件' : '从文件导入',
      ),
    ],
  );

  String _timestamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}_'
        '${two(n.hour)}${two(n.minute)}${two(n.second)}';
  }
}
