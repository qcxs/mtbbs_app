import 'dart:async';

/// 应用内事件总线 — 类似 Android Broadcast，完全解耦
///
/// 发布者无需知道谁在处理，订阅者自主选择感兴趣的事件。
///
/// 用法：
/// ```dart
/// // 发布
/// AppEventBus.fire(LoginExpiredEvent());
///
/// // 订阅
/// AppEventBus.stream.where((e) => e is LoginExpiredEvent).listen((_) {
///   context.push('/login');
/// });
/// ```
class AppEventBus {
  AppEventBus._();

  static final StreamController<AppEvent> _bus =
      StreamController<AppEvent>.broadcast();

  /// 事件流
  static Stream<AppEvent> get stream => _bus.stream;

  /// 发布事件
  static void fire(AppEvent event) => _bus.add(event);

  /// 关闭总线（一般在应用退出时调用）
  static void dispose() => _bus.close();
}

/// 事件基类
abstract class AppEvent {
  /// 事件标识，用于类型之外的过滤
  String get type => runtimeType.toString();
}

/// 登录过期事件 — 各组件可自行决定如何处理
class LoginExpiredEvent extends AppEvent {}

/// 设置变更事件 — CRUD 操作完成后广播，通知持久组件刷新
///
/// [scope] 标识变更范围，如 'tabOrder'、'shortcutLinks'、'toolbar'
class SettingsChangedEvent extends AppEvent {
  final String scope;
  SettingsChangedEvent(this.scope);

  @override
  String get type => 'settings:$scope';
}
