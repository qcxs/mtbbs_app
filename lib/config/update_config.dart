import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:mtbbs/config/build_config.dart';

/// 更新渠道。
///
/// 渠道决定「是否自动检查 / 能否下载」，不是编译模式：beta 也是 release 编译，
/// debug 只是未注入更新源的本地包。
enum UpdateChannel {
  /// 正式发布（GitHub Release + 自动检查）
  release,

  /// 预发布测试包（与正式版独立安装，通常只有 Actions artifact）
  beta,

  /// 调试包（手动检查仅用于排查）
  debug,
}

/// 更新产物所处的平台。判定见 `UpdateService.currentPlatform`。
enum UpdatePlatform { android, windows, ohos, other }

/// 更新源（GitHub 仓库）。
class UpdateSource {
  const UpdateSource({required this.owner, required this.name});

  final String owner;
  final String name;

  String get repoUrl => 'https://github.com/$owner/$name';

  String get releasesApiUrl =>
      'https://api.github.com/repos/$owner/$name/releases';
}

/// 单个平台的安装包匹配规则。
///
/// 默认只按后缀匹配（不锁文件名前缀），这样 fork 即使改了产物命名也能命中；
/// 同一仓库存在多个同类产物时，再通过 [namePrefix] 收窄。
class AssetRule {
  const AssetRule({
    required this.suffix,
    this.namePrefix = '',
    this.preferAbi = false,
  });

  /// 产物后缀，如 `.apk` / `_x64_setup.exe` / `.hap`
  final String suffix;

  /// 可选的文件名前缀（如 `MTBBS_ohos_`）；空 = 不限制
  final String namePrefix;

  /// 多个命中时是否按设备 ABI 优先（Android / HarmonyOS）
  final bool preferAbi;

  bool matches(String assetName) =>
      assetName.endsWith(suffix) &&
      (namePrefix.isEmpty || assetName.contains(namePrefix));
}

/// 单个渠道的行为策略。
class UpdatePolicy {
  const UpdatePolicy({
    required this.autoCheck,
    required this.manualCheck,
    required this.canDownload,
    this.includePrerelease = false,
  });

  /// 启动时是否自动检查（仍受设置项与 1 小时限流约束）
  final bool autoCheck;

  /// 是否提供「检查更新」手动入口
  final bool manualCheck;

  /// 是否显示「下载」按钮；false 时只展示版本信息 / 打开发布页
  final bool canDownload;

  /// 是否接受 GitHub 的 pre-release
  final bool includePrerelease;
}

/// 应用内更新配置。
///
/// 唯一事实源是构建期注入的 `mtbbs.repo` / `mtbbs.channel`
/// （见 [BuildConfig] 与 `scripts/version.ps1`）。**未注入 `mtbbs.repo`
/// 的构建视为本地测试包，完全不检查更新**。
class UpdateConfig {
  const UpdateConfig({
    required this.source,
    required this.channel,
    this.policies = defaultPolicies,
    this.assetRules = defaultAssetRules,
  });

  final UpdateSource source;
  final UpdateChannel channel;
  final Map<UpdateChannel, UpdatePolicy> policies;
  final Map<UpdatePlatform, List<AssetRule>> assetRules;

  UpdatePolicy get policy => policies[channel] ?? defaultPolicies[channel]!;

  List<AssetRule> rulesFor(UpdatePlatform platform) =>
      assetRules[platform] ?? const [];

  /// 从构建期注入项解析；未注入或格式非法时返回 null（不检查更新）。
  static UpdateConfig? fromBuildConfig() {
    final repo = BuildConfig.updateRepo.trim();
    final parts = repo.split('/');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) return null;
    return UpdateConfig(
      source: UpdateSource(owner: parts[0], name: parts[1]),
      channel: parseChannel(BuildConfig.updateChannel) ?? defaultChannel(),
    );
  }

  /// 解析渠道字符串；未知值返回 null，由调用方回落到 [defaultChannel]。
  static UpdateChannel? parseChannel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'release':
        return UpdateChannel.release;
      case 'beta':
        return UpdateChannel.beta;
      case 'debug':
        return UpdateChannel.debug;
      default:
        return null;
    }
  }

  /// 未显式注入渠道时的推断：beta 形态 → beta；release 编译 → release；其余 → debug。
  static UpdateChannel defaultChannel() {
    if (BuildConfig.isBeta) return UpdateChannel.beta;
    return kReleaseMode ? UpdateChannel.release : UpdateChannel.debug;
  }

  /// 默认渠道策略。
  ///
  /// beta / debug 不自动检查、不提供下载：beta 只发 Actions artifact，
  /// 且独立 applicationId 装不了正式包；debug 只用于手动排查。
  static const Map<UpdateChannel, UpdatePolicy> defaultPolicies = {
    UpdateChannel.release: UpdatePolicy(
      autoCheck: true,
      manualCheck: true,
      canDownload: true,
    ),
    UpdateChannel.beta: UpdatePolicy(
      autoCheck: false,
      manualCheck: true,
      canDownload: false,
      includePrerelease: true,
    ),
    UpdateChannel.debug: UpdatePolicy(
      autoCheck: false,
      manualCheck: true,
      canDownload: false,
      includePrerelease: true,
    ),
  };

  /// 默认选包规则。
  ///
  /// 只按后缀匹配，不锁 `MTBBS_*` 前缀——下游/fork 改产物名后无需改代码；
  /// 需要收窄时给 [AssetRule.namePrefix] 传值即可。
  static const Map<UpdatePlatform, List<AssetRule>> defaultAssetRules = {
    UpdatePlatform.android: [
      AssetRule(suffix: '.apk', preferAbi: true),
    ],
    UpdatePlatform.windows: [
      AssetRule(suffix: '_x64_setup.exe'),
    ],
    UpdatePlatform.ohos: [
      AssetRule(suffix: '.hap', preferAbi: true),
      AssetRule(suffix: '.app', preferAbi: true),
    ],
  };
}
