import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:http/http.dart' as http;
import 'package:mtbbs/config/build_config.dart';
import 'package:mtbbs/config/update_config.dart';
import 'package:mtbbs/core/app/app_capabilities.dart';
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

/// 检查失败（网络 / 接口异常 / 未配置更新源）
class UpdateCheckFailed extends UpdateCheckResult {
  const UpdateCheckFailed(this.message);

  final String message;
}

/// 应用内更新检查
///
/// 更新源与渠道来自构建期注入（[BuildConfig.updateRepo] / `updateChannel`）：
/// - **未注入 `mtbbs.repo`** → [config] 为 null，完全不检查（本地测试包）；
/// - 注入后按 [UpdateConfig.policy] 决定自动检查 / 手动检查 / 能否下载。
///
/// 判新依据：GitHub Release 创建时间晚于本包构建时间（[BuildConfig.buildTime]）。
/// `versionName` 带 9 位提交 hash 后缀，语义化比较需额外剥后缀，构建时间无此问题。
class UpdateService {
  UpdateService._();

  static final UpdateService instance = UpdateService._();

  /// 构建期注入的更新配置；null = 未注入更新源（不检查更新）。
  final UpdateConfig? config = UpdateConfig.fromBuildConfig();

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

  /// 是否配置了更新源。未配置时关于页不显示任何更新入口。
  bool get isConfigured => config != null;

  /// 启动时是否自动检查（仍受设置项与 [autoCheckDue] 限流约束）
  bool get autoCheckEnabled => config?.policy.autoCheck ?? false;

  /// 是否提供手动「检查更新」入口
  bool get manualCheckEnabled => config?.policy.manualCheck ?? false;

  /// 是否显示「下载」按钮（false 时只能打开发布页）
  bool get canDownload => config?.policy.canDownload ?? false;

  /// 自动检查的最小间隔：发布没有那么频繁，1 小时内不重复请求。
  static const Duration autoCheckInterval = Duration(hours: 1);

  /// 距离上次检查是否已超过 [autoCheckInterval]。
  ///
  /// [lastCheckAt] 为 Unix 秒；0 表示从未检查。
  static bool autoCheckDue(int lastCheckAt, {DateTime? now}) {
    if (lastCheckAt <= 0) return true;
    final currentSeconds =
        (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    return currentSeconds - lastCheckAt >= autoCheckInterval.inSeconds;
  }

  /// 拉取最新 Release 并判断是否有更新
  Future<UpdateCheckResult> check() async {
    final cfg = config;
    if (cfg == null) return const UpdateCheckFailed('未配置更新源');
    if (_inFlight) return const UpdateCheckFailed('正在检查');
    _inFlight = true;
    checking.value = true;
    try {
      final resp = await http.get(
        Uri.parse(cfg.source.releasesApiUrl),
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
      final releases = decoded
          .whereType<Map<String, dynamic>>()
          .where((e) => e['draft'] != true)
          .where(
            (e) =>
                cfg.policy.includePrerelease || e['prerelease'] != true,
          )
          .toList();
      if (releases.isEmpty) {
        return const UpdateCheckFailed('未找到发布记录');
      }
      // 不依赖接口顺序：按 created_at 取最新一条
      Map<String, dynamic>? latest;
      DateTime? createdAt;
      for (final e in releases) {
        final at = DateTime.tryParse('${e['created_at']}');
        if (at == null) continue;
        if (createdAt == null || at.isAfter(createdAt)) {
          latest = e;
          createdAt = at;
        }
      }
      if (latest == null || createdAt == null) {
        return const UpdateCheckFailed('发布数据缺少时间');
      }
      final info = _parseRelease(latest, createdAt, cfg.source.repoUrl);
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

  /// 当前平台对应的选包规则分组
  UpdatePlatform get currentPlatform {
    // 鸿蒙必须先判：两套 SDK 的平台枚举/`Platform` 返回值不同
    if (AppCapabilities.isOhos) return UpdatePlatform.ohos;
    if (Platform.isAndroid) return UpdatePlatform.android;
    if (Platform.isWindows) return UpdatePlatform.windows;
    return UpdatePlatform.other;
  }

  /// 当前平台可用的下载地址；返回 null 表示需回退打开 Release 页
  String? downloadUrlFor(ReleaseInfo info) {
    final cfg = config;
    if (cfg == null) return null;
    return selectAsset(
      info.assets,
      cfg.rulesFor(currentPlatform),
      _abiName(),
    );
  }

  /// 按规则从产物列表中选包（纯函数，便于单测）。
  ///
  /// 规则按顺序尝试；命中多个时，`preferAbi` 规则先按设备 ABI 精确匹配，
  /// 再回退 arm64-v8a，最后取第一个。
  static String? selectAsset(
    List<ReleaseAsset> assets,
    List<AssetRule> rules,
    String abi,
  ) {
    for (final rule in rules) {
      final matched = assets.where((a) => rule.matches(a.name)).toList();
      if (matched.isEmpty) continue;
      if (!rule.preferAbi) return matched.first.downloadUrl;
      for (final a in matched) {
        if (a.name.contains(abi)) return a.downloadUrl;
      }
      for (final a in matched) {
        if (a.name.contains('arm64-v8a')) return a.downloadUrl;
      }
      return matched.first.downloadUrl;
    }
    return null;
  }

  ReleaseInfo _parseRelease(
    Map<String, dynamic> json,
    DateTime createdAt,
    String fallbackRepoUrl,
  ) {
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
      htmlUrl: '${json['html_url'] ?? fallbackRepoUrl}',
      createdAt: createdAt,
      assets: assets,
    );
  }

  /// 当前设备 ABI（非 Android/鸿蒙平台返回默认值，不影响无 ABI 规则的平台）
  String _abiName() {
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
