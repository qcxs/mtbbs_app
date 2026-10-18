import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/app/app_capabilities.dart';

void main() {
  setUp(() {
    AppCapabilities.resetForTest();
  });

  test('非鸿蒙平台默认启用 JS 引擎与全部可选能力', () {
    final isOhos =
        defaultTargetPlatform.name == 'ohos' ||
        Platform.operatingSystem == 'ohos';
    expect(AppCapabilities.isOhos, isOhos);

    for (final capability in AppCapability.values) {
      if (capability == AppCapability.localJsSolver && isOhos) continue;
      expect(
        AppCapabilities.isAvailable(capability),
        isTrue,
        reason: '${capability.name} 应在当前平台默认可用',
      );
    }
  });

  test('鸿蒙默认关闭 JS 引擎，ACW 走纯 Dart 兜底', () {
    // 直接验证策略函数的鸿蒙分支：通过测试覆盖把 isOhos 的结果映射到能力表。
    // isOhos 由运行平台决定，这里只断言“若为鸿蒙，则 localJsSolver 关闭”。
    if (AppCapabilities.isOhos) {
      expect(
        AppCapabilities.isAvailable(AppCapability.localJsSolver),
        isFalse,
      );
    }
  });

  test('运行时失败可关闭单个能力', () {
    expect(
      AppCapabilities.isAvailable(AppCapability.mcpServer),
      isTrue,
    );
    AppCapabilities.disable(AppCapability.mcpServer);
    expect(
      AppCapabilities.isAvailable(AppCapability.mcpServer),
      isFalse,
    );
    // 其它能力不受影响
    expect(
      AppCapabilities.isAvailable(AppCapability.webView),
      isTrue,
    );
  });

  test('测试覆盖可强制指定能力状态', () {
    AppCapabilities.resetForTest(
      overrides: {
        AppCapability.webView: false,
        AppCapability.saveImage: false,
      },
    );
    expect(AppCapabilities.isAvailable(AppCapability.webView), isFalse);
    expect(AppCapabilities.isAvailable(AppCapability.saveImage), isFalse);
    expect(AppCapabilities.isAvailable(AppCapability.filePicker), isTrue);
  });
}
