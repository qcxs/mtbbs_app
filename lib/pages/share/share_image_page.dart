import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/core/utils/shortcut_helper.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/services/image_export.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';

/// 分享图勾选项（生成页的临时开关；默认全开、不持久化，切换即时生效）。
class ShareToggle {
  final String id;
  final String label;
  final bool initial;

  const ShareToggle({
    required this.id,
    required this.label,
    this.initial = true,
  });
}

/// 「生成图片」预览页骨架（帖子卡 / 个人主页卡共用）。
///
/// 只负责通用部分：**强制浅色**预览、截图边界（[CaptureBoundary]）、勾选项、
/// 保存（移动端存相册 / 桌面另存为）、Esc 返回。具体渲染哪张卡片由 [cardBuilder]
/// 决定，并通过 [enabled]（当前勾选中的 id 集合）感知选项状态。
class ShareImagePage extends StatefulWidget {
  /// 文件名前缀，最终为 `{prefix}_{时间戳}`
  final String filePrefix;

  /// 勾选项（空列表 = 不显示勾选栏）
  final List<ShareToggle> toggles;

  final Widget Function(BuildContext context, Set<String> enabled) cardBuilder;

  const ShareImagePage({
    super.key,
    required this.filePrefix,
    this.toggles = const [],
    required this.cardBuilder,
  });

  /// 以全屏路由打开。
  ///
  /// 推到 **root navigator** → 是 ShellRoute 的兄弟路由，不在 `GlobalShortcutsWrapper`
  /// 覆盖范围内，故本页自带一份 Esc 返回绑定（见 build）。
  static Future<void> open(
    BuildContext context, {
    required String filePrefix,
    List<ShareToggle> toggles = const [],
    required Widget Function(BuildContext context, Set<String> enabled)
    cardBuilder,
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => ShareImagePage(
          filePrefix: filePrefix,
          toggles: toggles,
          cardBuilder: cardBuilder,
        ),
      ),
    );
  }

  @override
  State<ShareImagePage> createState() => _ShareImagePageState();
}

class _ShareImagePageState extends State<ShareImagePage> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _saving = false;
  late final Map<String, bool> _on = {
    for (final t in widget.toggles) t.id: t.initial,
  };

  Set<String> get _enabled => {
    for (final e in _on.entries)
      if (e.value) e.key,
  };

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      // 等当前帧绘制完成，保证 RepaintBoundary 已上屏再截
      await WidgetsBinding.instance.endOfFrame;
      final bytes = await ImageExport.capturePng(_boundaryKey);
      if (!mounted) return;
      if (bytes == null) {
        showToast('生成图片失败');
        return;
      }
      final outcome = await ImageExport.save(
        bytes,
        fileName: '${widget.filePrefix}_${_timestamp()}',
      );
      if (!mounted) return;
      switch (outcome) {
        case SaveImageOutcome.saved:
          showToast(
            Platform.isAndroid || Platform.isIOS ? '已保存到相册' : '图片已保存',
          );
        case SaveImageOutcome.permissionDenied:
          showToast('未获得相册权限，无法保存');
        case SaveImageOutcome.failed:
          showToast('保存失败');
        case SaveImageOutcome.canceled:
          break;
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _timestamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}'
        '${two(n.hour)}${two(n.minute)}${two(n.second)}';
  }

  @override
  Widget build(BuildContext context) {
    // 分享卡固定浅色：用当前种子色生成浅色方案，保证品牌一致又不受夜间模式影响
    final settings = context.read<SettingsProvider>();
    final lightTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: settings.seedColor,
        brightness: Brightness.light,
      ),
    );
    // Esc（或用户自定义的「返回」快捷键）关闭本页：本页 push 到 root，是 ShellRoute
    // 的兄弟路由，不在 GlobalShortcutsWrapper（挂在 ShellRoute 外层）覆盖范围内。
    final backKey = ShortcutHelper.parse(settings.shortcut('goBack'));
    return CallbackShortcuts(
      bindings: {?backKey: () => Navigator.of(context).maybePop()},
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black.withValues(alpha: 0.82),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    child: Center(
                      child: CaptureBoundary(
                        key: _boundaryKey,
                        child: Theme(
                          data: lightTheme,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 460),
                            child: widget.cardBuilder(context, _enabled),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // 生成选项 + 操作栏：勾选为临时项，切换即时刷新预览
                Container(
                  color: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: 0.94),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.toggles.isNotEmpty) _buildOptions(),
                      _buildBar(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOptions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        alignment: WrapAlignment.center,
        children: [
          for (final t in widget.toggles)
            FilterChip(
              label: Text(t.label),
              selected: _on[t.id] ?? false,
              onSelected: (v) => setState(() => _on[t.id] = v),
            ),
        ],
      ),
    );
  }

  Widget _buildBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton.filledTonal(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close),
            tooltip: '关闭',
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_alt, size: 18),
            label: const Text('保存图片'),
          ),
        ],
      ),
    );
  }
}
