import 'package:mtbbs/auth/providers/auth_provider.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/core/app/session_registry.dart';
import 'package:mtbbs/core/app/site_store.dart';

/// 应用编排器 — 统一管理站点/用户切换等跨模块操作
///
/// 将原来的 N 步手动编排简化为 1 个方法，避免调用方漏步骤。
class AppOrchestrator {
  final SettingsProvider settings;
  final AuthProvider auth;

  AppOrchestrator({required this.settings, required this.auth});

  /// 切换站点（完整流程）
  ///
  /// 1. 保存旧站点的活跃账号
  /// 2. 持久化新站点索引
  /// 3. SiteStore.switchTo → notifyListeners + SiteChangedEvent
  /// 4. 加载 per-site 配置
  /// 5. 恢复新站点的账号上下文（全局 Dio 换成新站点的罐）
  /// 6. 重建跨站会话（旧站点改为作用域会话，新站点交回全局 Dio）
  Future<void> switchSite(int index) async {
    auth.saveCurrentSiteState();
    await settings.switchSite(index);
    SiteStore.instance.switchTo(index);
    await settings.reloadSiteConfig();
    await auth.onSiteChanged();
    // 必须放在全局 Dio 已经离开旧站点之后：当前站点不建作用域会话（见
    // `SessionRegistry.refreshHost`），切站后要重建，否则新当前站点还留着旧的
    // 作用域 Dio —— 它与全局活跃罐指向同一份磁盘目录，两个 `PersistCookieJar`
    // 实例彼此覆盖，人机验证 cookie 被写回旧值（docs/27）。
    await SessionRegistry.instance.reloadAll();
  }
}
