import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/config/update_config.dart';
import 'package:mtbbs/services/update_service.dart';

void main() {
  group('选包规则', () {
    const assets = [
      ReleaseAsset(
        name: 'MTBBS_android_1.2.0_arm64-v8a.apk',
        downloadUrl: 'apk-arm64',
      ),
      ReleaseAsset(
        name: 'MTBBS_android_1.2.0_armeabi-v7a.apk',
        downloadUrl: 'apk-arm',
      ),
      ReleaseAsset(
        name: 'MTBBS_android_1.2.0_x86_64.apk',
        downloadUrl: 'apk-x64',
      ),
      ReleaseAsset(
        name: 'MTBBS_windows_1.2.0_x64_setup.exe',
        downloadUrl: 'win-exe',
      ),
      ReleaseAsset(
        name: 'MTBBS_ohos_1.2.0_arm64-v8a.hap',
        downloadUrl: 'ohos-hap',
      ),
    ];

    List<AssetRule> rules(UpdatePlatform platform) =>
        UpdateConfig.defaultAssetRules[platform] ?? const [];

    test('Android 按设备 ABI 精确匹配', () {
      expect(
        UpdateService.selectAsset(
          assets,
          rules(UpdatePlatform.android),
          'armeabi-v7a',
        ),
        'apk-arm',
      );
      expect(
        UpdateService.selectAsset(
          assets,
          rules(UpdatePlatform.android),
          'x86_64',
        ),
        'apk-x64',
      );
    });

    test('Android ABI 无精确项时回退 arm64-v8a', () {
      expect(
        UpdateService.selectAsset(
          assets,
          rules(UpdatePlatform.android),
          'unknown-abi',
        ),
        'apk-arm64',
      );
    });

    test('鸿蒙选 .hap', () {
      expect(
        UpdateService.selectAsset(
          assets,
          rules(UpdatePlatform.ohos),
          'arm64-v8a',
        ),
        'ohos-hap',
      );
    });

    test('Windows 选 setup.exe', () {
      expect(
        UpdateService.selectAsset(
          assets,
          rules(UpdatePlatform.windows),
          'arm64-v8a',
        ),
        'win-exe',
      );
    });

    test('无匹配产物返回 null（由 UI 回退发布页）', () {
      expect(
        UpdateService.selectAsset(
          assets,
          rules(UpdatePlatform.other),
          'arm64-v8a',
        ),
        isNull,
      );
      expect(
        UpdateService.selectAsset(
          const [],
          rules(UpdatePlatform.android),
          'arm64-v8a',
        ),
        isNull,
      );
    });

    test('支持无前缀的 fork 产物命名', () {
      const forkAssets = [
        ReleaseAsset(name: 'app-release.apk', downloadUrl: 'fork-apk'),
      ];
      expect(
        UpdateService.selectAsset(
          forkAssets,
          rules(UpdatePlatform.android),
          'arm64-v8a',
        ),
        'fork-apk',
      );
    });
  });

  group('自动检查限流', () {
    final now = DateTime(2026, 1, 1, 12);
    int secondsAt(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;

    test('从未检查过 → 立即可检查', () {
      expect(UpdateService.autoCheckDue(0, now: now), isTrue);
    });

    test('1 小时内不重复检查', () {
      expect(
        UpdateService.autoCheckDue(
          secondsAt(now.subtract(const Duration(minutes: 59))),
          now: now,
        ),
        isFalse,
      );
    });

    test('超过 1 小时允许再次检查', () {
      expect(
        UpdateService.autoCheckDue(
          secondsAt(now.subtract(const Duration(hours: 1))),
          now: now,
        ),
        isTrue,
      );
    });
  });

  group('渠道策略', () {
    test('release 自动检查且可下载', () {
      final policy = UpdateConfig.defaultPolicies[UpdateChannel.release]!;
      expect(policy.autoCheck, isTrue);
      expect(policy.manualCheck, isTrue);
      expect(policy.canDownload, isTrue);
      expect(policy.includePrerelease, isFalse);
    });

    test('beta / debug 不自动检查、不可下载', () {
      for (final channel in [UpdateChannel.beta, UpdateChannel.debug]) {
        final policy = UpdateConfig.defaultPolicies[channel]!;
        expect(policy.autoCheck, isFalse, reason: channel.name);
        expect(policy.manualCheck, isTrue, reason: channel.name);
        expect(policy.canDownload, isFalse, reason: channel.name);
        expect(policy.includePrerelease, isTrue, reason: channel.name);
      }
    });
  });

  group('构建注入', () {
    test('未注入 mtbbs.repo → 不启用更新检查', () {
      expect(UpdateConfig.fromBuildConfig(), isNull);
    });

    test('渠道解析只接受已知值', () {
      expect(UpdateConfig.parseChannel('release'), UpdateChannel.release);
      expect(UpdateConfig.parseChannel('BETA'), UpdateChannel.beta);
      expect(UpdateConfig.parseChannel(' debug '), UpdateChannel.debug);
      expect(UpdateConfig.parseChannel('nightly'), isNull);
      expect(UpdateConfig.parseChannel(''), isNull);
    });
  });
}
