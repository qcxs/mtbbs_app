/// 构建期注入的发布元数据。
///
/// 由 [scripts/version.ps1] 读取 pubspec.yaml 版本名 + git 提交数，生成
/// `mtbbs_release.json`；打包/CI 时通过 `--dart-define-from-file` 注入。
/// 本地 `flutter run` 未注入时全部回落默认值（SNAPSHOT / 0 / N/A）。
///
/// 与 PiliPlus 的 `lib/build_config.dart` 同思路，key 前缀统一为 `mtbbs.`。
abstract final class BuildConfig {
  /// 版本名（如 1.0.0；Android 发布包为 1.0.0-<短 commit hash>）
  static const String versionName = String.fromEnvironment(
    'mtbbs.name',
    defaultValue: 'SNAPSHOT',
  );

  /// 构建号 = git 提交总数（`git rev-list --count HEAD`，单调递增）
  static const int versionCode = int.fromEnvironment(
    'mtbbs.code',
    defaultValue: 0,
  );

  /// 构建时的 git commit hash（完整 40 位）
  static const String commitHash = String.fromEnvironment(
    'mtbbs.hash',
    defaultValue: 'N/A',
  );

  /// 构建时间（Unix 秒），可用于应用内更新检查比对
  static const int buildTime = int.fromEnvironment(
    'mtbbs.time',
    defaultValue: 0,
  );

  /// 是否为 beta 形态（独立应用）。
  ///
  /// beta 也是 `--release` 编译，故更新检查不能只判 `kReleaseMode`；这里两条
  /// 来源都覆盖：Android beta 传了 `--dart-define=BETA=true`，Windows beta 无该
  /// define 但版本名固定为 `1.0.0-beta`（见 scripts/version.ps1）。
  static bool get isBeta =>
      const bool.fromEnvironment('BETA') || versionName.contains('-beta');

  /// 更新源仓库（`owner/repo`），由 `scripts/version.ps1 -Repo` 注入。
  ///
  /// **为空表示构建时未注入更新配置**（直接 `flutter build` / 未传 `-Repo`
  /// 的本地包）：不检查更新，关于页也不显示更新入口。
  static const String updateRepo = String.fromEnvironment(
    'mtbbs.repo',
    defaultValue: '',
  );

  /// 更新渠道（`release` / `beta` / `debug`），由 `-Channel` 注入；
  /// 留空时按构建形态推断，见 `UpdateConfig.defaultChannel`。
  static const String updateChannel = String.fromEnvironment(
    'mtbbs.channel',
    defaultValue: '',
  );

  /// 上游仓库地址（仅用于展示；fork 注入 `mtbbs.repo` 后 [repoUrl] 指向自己）。
  static const String upstreamRepoUrl = 'https://github.com/qcxs/mtbbs_app';

  /// 应用内展示的仓库地址：优先构建注入的更新源，未注入时回落上游。
  static String get repoUrl {
    final repo = updateRepo.trim();
    return repo.isEmpty ? upstreamRepoUrl : 'https://github.com/$repo';
  }
}
