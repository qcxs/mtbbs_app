import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show ValueNotifier, kReleaseMode;
import 'package:http/http.dart' as http;
import 'package:mtbbs/config/build_config.dart';
import 'package:mtbbs/core/utils/logger.dart';

/// 单个发布产物（安装包）
class ReleaseAsset {
  const ReleaseAsset({required this.name, required this.downloadUrl});

  final String name;
  final String downloadUrl;
}

/// GitHub Release 信息
class ReleaseInfo {
  const ReleaseInfo({
    required this.tagName,
    required this.body,
    required this.htmlUrl,
    required this.createdAt,
    required this.assets,
  });

  /// 发布 tag（如 v1.0.0）
  final String tagName;

  /// 更新说明（Release 正文）
  final String body;

  /// Release 页面地址（找不到匹配产物时回退打开）
  final String htmlUrl;

  /// 发布时间
  final DateTime createdAt;

  final List<ReleaseAsset> assets;
}

/// 更新检查结果
sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

/// 有新版本
class UpdateAvailable extends UpdateCheckResult {
  const UpdateAvailable(this.info);

  final ReleaseInfo info;
}

/// 已是最新版本
class UpdateUpToDate extends UpdateCheckResult {
  const UpdateUpToDate();
}

/// 检查失败（网络 / 接口异常）
class UpdateCheckFailed extends UpdateCheckResult {
  const UpdateCheckFailed(this.message);

  final String message;
}

/// 应用内更新检查
///
/// 仅正式版生效：debug / beta 都不检查。注意 beta 也是 `--release` 编译，
/// 所以**不能**只判 [kReleaseMode]，还需排除 beta，见 [isSupported]。
///
/// 判新依据与 PiliPlus 一致：GitHub Release 创建时间晚于本包构建时间
/// （[BuildConfig.buildTime]）即视为有新版本。`versionName` 带 9 位提交 hash
/// 后缀，语义化比较需额外剥后缀，构建时间无此问题。
class UpdateService {
  UpdateService._();

  static final UpdateService instance = UpdateService._();

  /// 最近一次成功检测到的最新发布（供关于页展示「最新版本」）。
  ///
  /// 只有检测成功（接口返回并解析成功）才写入，失败保持原值；因此"有值"
  /// 即代表曾经检测成功过。内存态、不持久化——它反映的是当前会话的真实结果。
  final ValueNotifier<ReleaseInfo?> latestRelease = ValueNotifier<ReleaseInfo?>(
    null,
  );

  /// 是否正在检查更新 —— 供 UI 显示进度。
  ///
  /// 放在服务层而不是某个页面的 State：手动检查的入口有两个（关于页、设置搜索），
  /// 状态跟着服务走才能两处一致。
  final ValueNotifier<bool> checking = ValueNotifier<bool>(false);

  bool _inFlight = false;

  /// 仅正式版支持：release 编译且非 beta
  bool get isSupported => kReleaseMode && !BuildConfig.isBeta;

  /// 拉取最新 Release 并判断是否有更新
  Future<UpdateCheckResult> check() async {
    if (_inFlight) return const UpdateCheckFailed('正在检查');
    _inFlight = true;
    checking.value = true;
    try {
      final resp = await http.get(
        Uri.parse(BuildConfig.releasesApiUrl),
        headers: const {
          // GitHub API 强制要求 User-Agent，缺失会被 403 拒回
          'User-Agent': 'MTBBS-App',
          'Accept': 'application/vnd.github+json',
        },
      );
      if (resp.statusCode != 200) {
        return UpdateCheckFailed('GitHub 接口返回 ${resp.statusCode}');
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is! List || decoded.isEmpty) {
        return const UpdateCheckFailed('GitHub 接口未返回发布数据');
      }
      // 列表按创建时间倒序，取最新一条非草稿发布
      final latest = decoded.whereType<Map<String, dynamic>>().firstWhere(
        (e) => e['draft'] != true,
        orElse: () => <String, dynamic>{},
      );
      if (latest.isEmpty) {
        return const UpdateCheckFailed('未找到发布记录');
      }
      final createdAt = DateTime.tryParse('${latest['created_at']}');
      if (createdAt == null) {
        return const UpdateCheckFailed('发布数据缺少时间');
      }
      final info = _parseRelease(latest, createdAt);
      // 解析成功即记录最新版本（有值代表检测成功）
      latestRelease.value = info;
      if (createdAt.millisecondsSinceEpoch ~/ 1000 > BuildConfig.buildTime) {
        return UpdateAvailable(info);
      }
      return const UpdateUpToDate();
    } catch (e) {
      AppLogger.d('UPDATE', '检查更新失败: $e');
      return UpdateCheckFailed('$e');
    } finally {
      _inFlight = false;
      checking.value = false;
    }
  }

  /// 当前平台可用的下载地址；返回 null 表示需回退打开 Release 页
  String? downloadUrlFor(ReleaseInfo info) {
    if (Platform.isAndroid) {
      return _matchAndroidAsset(info.assets);
    }
    if (Platform.isWindows) {
      return _firstBySuffix(info.assets, '_setup.exe');
    }
    return null;
  }

  ReleaseInfo _parseRelease(Map<String, dynamic> json, DateTime createdAt) {
    final assets = (json['assets'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(
          (a) => ReleaseAsset(
            name: '${a['name']}',
            downloadUrl: '${a['browser_download_url']}',
          ),
        )
        .toList();
    return ReleaseInfo(
      tagName: '${json['tag_name'] ?? ''}',
      body: '${json['body'] ?? ''}',
      htmlUrl: '${json['html_url'] ?? BuildConfig.repoUrl}',
      createdAt: createdAt,
      assets: assets,
    );
  }

  /// 按当前设备 ABI 选 APK：精确匹配 → arm64-v8a → 任意 android 包
  String? _matchAndroidAsset(List<ReleaseAsset> assets) {
    final apks = assets
        .where(
          (a) => a.name.contains('MTBBS_android_') && a.name.endsWith('.apk'),
        )
        .toList();
    if (apks.isEmpty) return null;
    final abi = _androidAbi();
    for (final a in apks) {
      if (a.name.contains(abi)) return a.downloadUrl;
    }
    for (final a in apks) {
      if (a.name.contains('arm64-v8a')) return a.downloadUrl;
    }
    return apks.first.downloadUrl;
  }

  String? _firstBySuffix(List<ReleaseAsset> assets, String suffix) {
    for (final a in assets) {
      if (a.name.endsWith(suffix)) return a.downloadUrl;
    }
    return null;
  }

  /// 当前设备 ABI（仅 Android 调用；其它平台返回默认值）
  String _androidAbi() {
    switch (Abi.current()) {
      case Abi.androidArm64:
        return 'arm64-v8a';
      case Abi.androidArm:
        return 'armeabi-v7a';
      case Abi.androidX64:
        return 'x86_64';
      default:
        return 'arm64-v8a';
    }
  }
}
