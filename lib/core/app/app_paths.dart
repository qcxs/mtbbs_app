import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:mtbbs/config/site_config.dart';

/// 应用文件路径集中管理
///
/// 所有磁盘路径统一由此类提供，避免各模块各自调用 [getApplicationSupportDirectory] /
/// [getTemporaryDirectory] / [Directory.systemTemp] 导致路径散落。
///
/// **⚠️ 禁止使用 [getApplicationDocumentsDirectory] 存储 App 数据**
/// 该 API 在 Windows 上返回用户的 Documents 文件夹（公共路径），
/// 所有 App 内部数据应使用 [getApplicationSupportDirectory]（应用私有目录）。
///
/// 目录结构：
/// ```
/// {appDataDir}/                 ← 见 [appDataDir]
///   cookies/{host}/              — CookieJar 持久化（游客）
///   cookies/{host}/_shared/      — 站点共享罐（与账号无关的客户端级 cookie）
///   cookies/{host}/{account}/    — CookieJar 持久化（登录用户）
///   mtbbs.sembast                — sembast 数据库（纯 Dart，无需原生依赖）
///
/// {tempDir}/                    ← getTemporaryDirectory()
///   emoji_cache/                 — CacheManager 表情
///   avatar_cache/                — CacheManager 头像
///   image_cache/                 — CacheManager 图片
///   mtbbs_clip/                  — ClipboardPasteService 临时文件
/// ```
class AppPaths {
  AppPaths._();

  // ==================== 应用私有数据目录 ====================

  /// 应用私有数据根目录
  ///
  /// Windows release: `%APPDATA%\qcxs\mtbbs\`
  /// Windows debug:   `%APPDATA%\qcxs\mtbbs_debug\`
  /// Android:         `/data/data/{package}/app_flutter/`
  static Future<String> get appDataDir async {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ?? '';
      final suffix = kDebugMode ? '_debug' : '';
      return '$appData\\qcxs\\mtbbs$suffix';
    }
    return (await getApplicationSupportDirectory()).path;
  }

  // ==================== 临时目录 ====================

  static Future<String> get tempDir async =>
      (await getTemporaryDirectory()).path;

  // ==================== 数据库 ====================

  /// `{appDataDir}/mtbbs.sembast`
  static Future<String> get databasePath async =>
      '${await appDataDir}${p.separator}mtbbs.sembast';

  // ==================== Cookie ====================

  /// `{appDataDir}/cookies/`
  static Future<String> cookiesDir() async =>
      '${await appDataDir}/${SiteConfig.cookieDir}';

  /// `{appDataDir}/cookies/{host}/`
  static Future<String> cookiesDirForHost(String host) async =>
      '${await cookiesDir()}/$host';

  /// `{appDataDir}/cookies/{host}/{account}/`
  static Future<String> cookiesDirForAccount(
    String host,
    String account,
  ) async => '${await cookiesDirForHost(host)}/$account';

  /// 站点共享罐的目录名 —— 与账号目录同级，用下划线前缀避免与真实账号名混淆
  static const String sharedCookieDirName = '_shared';

  /// `{appDataDir}/cookies/{host}/_shared/`
  ///
  /// 存放**与账号无关的客户端级 cookie**（人机验证 / 防火墙下发的那些）。
  /// 与账号罐分开落盘，请求时由 `SiteCookieJar` 合并下发 —— 这样切账号、
  /// 切游客、重启都不会把验证 cookie 弄丢。
  static Future<String> sharedCookiesDirForHost(String host) async =>
      '${await cookiesDirForHost(host)}/$sharedCookieDirName';

  // ==================== 剪贴板临时文件 ====================

  /// `{tempDir}/mtbbs_clip/`
  static Future<String> get clipboardDir async => '${await tempDir}/mtbbs_clip';

  // ==================== 缓存统计/清空 ====================

  /// 获取缓存 key 对应的完整目录路径
  ///
  /// CacheManager 默认将缓存存在 `{tempDir}/{configKey}/` 下。
  static Future<String> cachePath(String configKey) async =>
      '${await tempDir}/$configKey';
}
