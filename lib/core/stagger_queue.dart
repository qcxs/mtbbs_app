import 'dart:async';

/// 通用错峰间隔（毫秒），对应设置项"通用错峰间隔"
Duration _staggerInterval = const Duration(milliseconds: 40);

/// 运行时调整错峰间隔。在 [SettingsProvider] 初始化完成后调用。
void setStaggerInterval(Duration interval) {
  _staggerInterval = interval;
}

// ==================== 队列实现 ====================

/// 错峰队列内部条目
class StaggerEntry {
  final Completer<void> completer = Completer<void>();
  bool cancelled = false;
}

final List<StaggerEntry> _queue = [];
bool _processing = false;

/// 错峰排队结果，用于等待或取消
class StaggerSlot {
  final StaggerEntry _entry;
  StaggerSlot(this._entry);

  /// 等待放行
  Future<void> get ready => _entry.completer.future;

  /// 取消本次排队（组件销毁时调用）
  void cancel() => _entry.cancelled = true;
}

/// 入队，返回 [StaggerSlot] 用于等待放行或取消
StaggerSlot enqueueStagger() {
  final entry = StaggerEntry();
  _queue.add(entry);
  if (!_processing) _process();
  return StaggerSlot(entry);
}

void _process() async {
  _processing = true;
  while (_queue.isNotEmpty) {
    final entry = _queue.removeAt(0);
    if (!entry.cancelled) {
      entry.completer.complete();
    }
    await Future.delayed(_staggerInterval);
  }
  _processing = false;
}
