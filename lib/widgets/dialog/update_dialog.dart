import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mtbbs/config/build_config.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/services/update_service.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';

/// 手动 / 自动检查更新并给出反馈。
///
/// - 自动检查（[isAuto]）= 仅正式版执行；该版本已被「跳过此版本」时静默；
/// - 手动检查 = 任何构建（含 debug / beta）都执行，且**总会弹窗**显示版本与
///   更新说明（便于排查"检测是否正确"）；无更新或非正式版时只给「关闭」；
/// - 检查失败：一律不做任何事（「最新版本」保持上次成功的结果）。
///
/// 「不再提醒」已由设置项「自动检查更新」开关替代，弹窗不再提供该按钮。
Future<void> checkForUpdate(
  BuildContext context, {
  required bool isAuto,
  required SettingsProvider settings,
}) async {
  final service = UpdateService.instance;
  // 自动检查仅正式版执行；手动检查在任何构建下都执行（便于 beta / debug 排查）
  if (isAuto && !service.isSupported) return;

  final result = await service.check();
  if (!context.mounted) return;

  switch (result) {
    case UpdateAvailable(:final info):
      // 自动检查：该版本已被跳过 → 静默；手动检查不受限（可取消跳过）
      if (isAuto && settings.skippedUpdateVersion == info.tagName) return;
      await _showReleaseDialog(
        context,
        title: '发现新版本',
        info: info,
        settings: settings,
        canUpdate: service.isSupported,
      );
    case UpdateUpToDate():
      if (isAuto) return;
      final info = service.latestRelease.value;
      if (info == null) return;
      await _showReleaseDialog(
        context,
        title: '已是最新版本',
        info: info,
        settings: settings,
        canUpdate: false,
      );
    case UpdateCheckFailed():
      // 检测失败不做任何事（「最新版本」保持上次成功的结果）
      break;
  }
}

/// 启动后调度一次自动检查（仅正式版 + 开关开启）。
///
/// 延迟几秒执行：不阻塞首帧，也不与启动期的站点请求抢带宽。供 main.dart 调用。
void scheduleAutoUpdateCheck(SettingsProvider settings) {
  if (!UpdateService.instance.isSupported || !settings.autoCheckUpdate) return;
  Future.delayed(const Duration(seconds: 3), () {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    checkForUpdate(ctx, isAuto: true, settings: settings);
  });
}

/// 统一的版本信息弹窗。
///
/// [canUpdate] 为 true（正式版 + 确有新版本）时展示「跳过此版本 / 关闭 / 下载」；
/// 否则只给「关闭」，仅作信息展示（debug / beta、或已是最新时走这条路）。
Future<void> _showReleaseDialog(
  BuildContext context, {
  required String title,
  required ReleaseInfo info,
  required SettingsProvider settings,
  required bool canUpdate,
}) {
  final cs = Theme.of(context).colorScheme;
  final downloadUrl = canUpdate
      ? UpdateService.instance.downloadUrlFor(info)
      : null;
  final isSkipped = settings.skippedUpdateVersion == info.tagName;

  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      constraints: const BoxConstraints(maxWidth: 400),
      title: _dialogTitle(title),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _infoRow(cs, '当前版本', 'v${BuildConfig.versionName}'),
              _infoRow(cs, '最新版本', info.tagName.isEmpty ? '—' : info.tagName),
              const SizedBox(height: 8),
              Text(
                info.body.trim().isEmpty ? '（本次发布未填写更新说明）' : info.body,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (canUpdate)
          TextButton(
            onPressed: () {
              settings.setSkippedUpdateVersion(isSkipped ? '' : info.tagName);
              Navigator.of(ctx).pop();
            },
            child: Text(
              isSkipped ? '取消跳过' : '跳过此版本',
              style: TextStyle(color: cs.outline),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text('关闭', style: TextStyle(color: cs.outline)),
        ),
        if (downloadUrl != null)
          FilledButton(
            onPressed: () => _openUrl(downloadUrl),
            child: const Text('下载'),
          ),
      ],
    ),
  );
}

Widget _dialogTitle(String text) => Text(
  text,
  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
);

Widget _infoRow(ColorScheme cs, String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

Future<void> _openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
