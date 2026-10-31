import 'package:flutter/services.dart';
import 'package:mtbbs/core/app/app_capabilities.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:url_launcher/url_launcher.dart';

/// 打开外部链接的结果
enum ExternalUrlOutcome { opened, unavailable, failed }

/// 打开外部链接（浏览器 / 应用市场）适配器。
///
/// 更新下载、Release 页等**更新入口**统一走这里：插件在当前平台缺失
/// （典型：鸿蒙未移植）时关闭能力并返回 [ExternalUrlOutcome.unavailable]，
/// 由调用方降级为复制链接（见 docs/23）。
abstract final class ExternalUrl {
  ExternalUrl._();

  static Future<ExternalUrlOutcome> open(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !uri.hasScheme) return ExternalUrlOutcome.failed;
    if (!AppCapabilities.isAvailable(AppCapability.openExternalUrl)) {
      return ExternalUrlOutcome.unavailable;
    }
    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      return opened ? ExternalUrlOutcome.opened : ExternalUrlOutcome.failed;
    } on MissingPluginException {
      AppLogger.w('UPDATE', 'url_launcher 无当前平台实现');
      AppCapabilities.disable(AppCapability.openExternalUrl);
      return ExternalUrlOutcome.unavailable;
    } on UnimplementedError {
      AppLogger.w('UPDATE', 'url_launcher 无当前平台实现');
      AppCapabilities.disable(AppCapability.openExternalUrl);
      return ExternalUrlOutcome.unavailable;
    } catch (e) {
      AppLogger.w('UPDATE', '打开链接失败：$e');
      return ExternalUrlOutcome.failed;
    }
  }
}
