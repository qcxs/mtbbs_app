import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/utils/shortcut_helper.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/services/image_export.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';
import 'package:mtbbs/widgets/share/share_qr_code.dart';

/// 个人主页「生成图片」预览。
///
/// 内容 = **页面正文区块原样**（由主页在其 `build` 中构建后传入）+ 底部一条
/// 「站点 / 用户 / 二维码」水印，因此既能与页面完全一致，又带来源与定位信息，
/// 且没有任何勾选项配置。
class UserSharePreview extends StatefulWidget {
  /// 页面正文区块。必须由**页面在其 build 中**构建后传入——
  /// 这样区块用的就是页面的主题与依赖（区块内会调用 `context.select`，
  /// 不能在 build 之外构建），渲染结果才与页面一致。
  final List<Widget> sections;

  /// 用户标识（水印里的"用户"：昵称 · uid）
  final String userLabel;

  /// 二维码内容（个人主页链接）
  final String qrUrl;

  /// 文件名前缀，最终为 `{prefix}_{时间戳}`
  final String filePrefix;

  /// 所属站点 host（跨站点用户主页用）；null = 当前站点
  final String? siteHost;

  final VoidCallback onClose;

  const UserSharePreview({
    super.key,
    required this.sections,
    required this.userLabel,
    required this.qrUrl,
    required this.filePrefix,
    this.siteHost,
    required this.onClose,
  });

  @override
  State<UserSharePreview> createState() => _UserSharePreviewState();
}

class _UserSharePreviewState extends State<UserSharePreview> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _saving = false;

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
        case SaveImageOutcome.unavailable:
          showToast('当前平台不支持保存图片');
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
    final cs = Theme.of(context).colorScheme;
    final settings = context.read<SettingsProvider>();
    // Esc（或用户自定义的「返回」快捷键）退出预览
    final backKey = ShortcutHelper.parse(settings.shortcut('goBack'));
    return CallbackShortcuts(
      bindings: {?backKey: widget.onClose},
      child: Focus(
        autofocus: true,
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.82),
          child: SafeArea(
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
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 460),
                          child: IgnorePointer(
                            // 与页面同底色（页面 Scaffold 的背景色）
                            child: Container(
                              width: double.infinity,
                              color: cs.surfaceContainerLow,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  ...widget.sections,
                                  _footer(cs),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.filledTonal(
                        onPressed: widget.onClose,
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_alt, size: 18),
                        label: const Text('保存图片'),
                      ),
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

  /// 底部水印：站点 + 用户 + 二维码（页面区块之外附加的来源 / 定位信息）
  Widget _footer(ColorScheme cs) {
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.asset(
              'assets/icon/app_icon.png',
              width: 24,
              height: 24,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MTBBS · ${widget.siteHost ?? SiteStore.instance.host}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (widget.userLabel.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      widget.userLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (widget.qrUrl.isNotEmpty) ...[
            const SizedBox(width: 10),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShareQrCode(data: widget.qrUrl),
                const SizedBox(height: 2),
                Text(
                  '扫码直达',
                  style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
