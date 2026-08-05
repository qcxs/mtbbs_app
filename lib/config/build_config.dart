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
}
