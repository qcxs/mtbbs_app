import 'package:flutter/material.dart';
import 'package:mtbbs/config/build_config.dart';
import 'package:mtbbs/core/utils/clipboard_helper.dart';
import 'package:mtbbs/platform/optional/external_url.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/services/update_service.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';

/// 手动 / 自动检查更新并给出反馈。
///
/// - 未注入更新源的构建（本地包）：不检查，关于页也不显示入口；
/// - 自动检查 = 仅渠道策略允许 + 开关开启 + 距上次检查超过 1 小时；
/// - 手动检查按渠道策略执行，且**总会弹窗**显示版本与更新说明（便于排查）；
/// - 检查失败：一律不做任何事（「最新版本」保持上次成功的结果）。
///
/// 「不再提醒」已由设置项「自动检查更新」开关替代，弹窗不再提供该按钮。
Future<void> checkForUpdate(
  BuildContext context, {
  required bool isAuto,
  required SettingsProvider settings,
}) async {
  final service = UpdateService.instance;
  if (!service.isConfigured) return;
  if (isAuto && !service.autoCheckEnabled) return;
  if (!isAuto && !service.manualCheckEnabled) return;

  final result = await service.check();
  // 记录本次检查时间（成功/失败都算），供启动自动检查的 1 小时限流使用
  await settings.setLastUpdateCheckAt(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
  );
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
        canDownload: service.canDownload,
        offerReleasePage: true,
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
        canDownload: false,
        offerReleasePage: false,
      );
    case UpdateCheckFailed():
      // 检测失败不做任何事（「最新版本」保持上次成功的结果）
      break;
  }
}

/// 启动后调度一次自动检查。
///
/// 条件：已注入更新源 + 渠道允许自动检查 + 设置开关开启 + 距上次检查超过
/// 1 小时（发布没有那么频繁，避免每次启动都打 GitHub API）。延迟几秒执行，
/// 不阻塞首帧，也不与启动期的站点请求抢带宽。供 main.dart 调用。
void scheduleAutoUpdateCheck(SettingsProvider settings) {
  final service = UpdateService.instance;
  if (!service.isConfigured || !service.autoCheckEnabled) return;
  if (!settings.autoCheckUpdate) return;
  if (!UpdateService.autoCheckDue(settings.lastUpdateCheckAt)) return;
  Future.delayed(const Duration(seconds: 3), () {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    checkForUpdate(ctx, isAuto: true, settings: settings);
  });
}

/// 统一的版本信息弹窗。
///
/// [canDownload] 为 true（正式渠道 + 确有新版本）时展示「跳过此版本 / 关闭 / 下载」；
/// 否则只给信息展示。找不到匹配产物时，[offerReleasePage] 为 true 会给出
/// 「打开发布页」——鸿蒙等尚无对应安装包形态时的兜底。
Future<void> _showReleaseDialog(
  BuildContext context, {
  required String title,
  required ReleaseInfo info,
  required SettingsProvider settings,
  required bool canDownload,
  required bool offerReleasePage,
}) {
  final cs = Theme.of(context).colorScheme;
  final downloadUrl = canDownload
      ? UpdateService.instance.downloadUrlFor(info)
      : null;
  final releasePageUrl = offerReleasePage && downloadUrl == null
      ? info.htmlUrl
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
        if (canDownload)
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
        if (releasePageUrl != null && releasePageUrl.isNotEmpty)
          TextButton(
            onPressed: () => _openUrl(ctx, releasePageUrl),
            child: const Text('打开发布页'),
          ),
        if (downloadUrl != null)
          FilledButton(
            onPressed: () => _openUrl(ctx, downloadUrl),
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

/// 打开发布页 / 下载地址；平台无法打开外部链接时复制链接兜底。
Future<void> _openUrl(BuildContext context, String url) async {
  final outcome = await ExternalUrl.open(url);
  if (outcome == ExternalUrlOutcome.opened) return;
  await ClipboardHelper.write(url);
  if (context.mounted) showToast('无法打开浏览器，链接已复制');
}
