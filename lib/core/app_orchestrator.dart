import '../auth/providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import 'site_store.dart';

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
  /// 5. 恢复新站点的账号上下文
  Future<void> switchSite(int index) async {
    auth.saveCurrentSiteState();
    await settings.switchSite(index);
    SiteStore.instance.switchTo(index);
    await settings.reloadSiteConfig();
    await auth.onSiteChanged();
  }
}
