import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/app/default_config.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/services/api_service.dart';

/// Windows 证书补丁（与 main.dart 的 _WindowsCertOverride 同款）
///
/// Flutter/Dart 在 Windows 上使用 BoringSSL，某些环境无法读取根证书，
/// 导致 HTTPS 握手失败。此处绕过校验，信任交由上层处理。
class WindowsCertOverride extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

/// 模拟 App 初始化序列（复刻 main.dart，去掉 UI 与数据库层）
///
/// 顺序：
/// 1. 初始化测试绑定（rootBundle 可用，defaults.json 可加载）
/// 2. 恢复真实网络（flutter_test 默认 mock 掉 HttpClient 返回 400）
///    + 套用 Windows 证书补丁
/// 3. 加载默认配置 → 初始化站点 → 初始化 ApiService（复用 App 的 Cookie 目录）
/// 4. 切换 Cookie：指定 [account] 用其登录态，否则用游客态
///
/// [site] 指定站点（索引数字或站点名，空 = 默认第一个站点），
/// 用于跨站点测试（如吾爱破解与 MT 论坛使用同一套 API 层）。
Future<void> bootstrap({String account = '', String site = ''}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test 会安装 _MockHttpOverrides（所有请求返回 400），
  // 必须用真实 HttpOverrides 覆盖才能发真实网络请求。
  HttpOverrides.global = WindowsCertOverride();

  await DefaultConfig.instance.load();
  SiteStore.instance.init();
  if (site.isNotEmpty) {
    final byIndex = int.tryParse(site);
    final target =
        byIndex ?? SiteStore.instance.sites.indexWhere((s) => s.name == site);
    if (target > 0) SiteStore.instance.switchTo(target);
  }
  await ApiService().init(baseUrl: SiteStore.instance.baseUrl);
  if (account.isNotEmpty) {
    await ApiService().switchToAccount(account);
  } else {
    await ApiService().switchToGuest();
  }
}
