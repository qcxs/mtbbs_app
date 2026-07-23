import 'dart:async';
import '../config/site_config.dart';

/// 应用内事件总线 — 完全解耦的广播通知机制
///
/// 发布者无需知道谁在处理，订阅者自主选择感兴趣的事件。
///
/// 用法：
/// ```dart
/// // 发布
/// EventBus.fire(LoginExpiredEvent());
///
/// // 订阅
/// EventBus.stream.where((e) => e is LoginExpiredEvent).listen((_) { ... });
/// ```
class EventBus {
  EventBus._();

  static final StreamController<AppEvent> _bus =
      StreamController<AppEvent>.broadcast();

  static Stream<AppEvent> get stream => _bus.stream;

  static void fire(AppEvent event) => _bus.add(event);

  static void dispose() => _bus.close();
}

/// 事件基类
abstract class AppEvent {
  String get type => runtimeType.toString();
}

/// 登录过期事件
class LoginExpiredEvent extends AppEvent {}

/// 站点切换事件 — 非 Widget 层订阅后自动响应
///
/// [previous] 切换前站点，[current] 切换后站点。
/// Widget 层应直接 `context.watch<SiteStore>()` 获得响应式更新。
class SiteChangedEvent extends AppEvent {
  final Site previous;
  final Site current;
  SiteChangedEvent({required this.previous, required this.current});

  String get host => current.host;
}

/// 用户切换事件 — 账号切换后广播
class UserChangedEvent extends AppEvent {
  final String? previousUid;
  final String? currentUid;
  UserChangedEvent({this.previousUid, this.currentUid});
}

/// 设置变更事件 — CRUD 操作完成后广播，通知持久组件刷新
///
/// [scope] 标识变更范围，如 'tabOrder'、'shortcutLinks'、'toolbar'
class SettingsChangedEvent extends AppEvent {
  final String scope;
  SettingsChangedEvent(this.scope);

  @override
  String get type => 'settings:$scope';
}
