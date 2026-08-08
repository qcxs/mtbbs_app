import 'dart:ui';

import 'package:mtbbs/core/utils/database_helper.dart';

/// 桌面窗口状态持久化（统一走 DatabaseHelper，符合铁律 5）
///
/// 记忆窗口尺寸/位置/最大化状态，下次启动恢复。
class WindowStateStore {
  static const String _kWidth = 'windowWidth';
  static const String _kHeight = 'windowHeight';
  static const String _kX = 'windowX';
  static const String _kY = 'windowY';
  static const String _kMaximized = 'windowMaximized';

  /// 加载已保存的窗口状态；无记录返回 null
  static Future<({Size size, Offset position, bool maximized})?> load() async {
    final db = DatabaseHelper.instance;
    final w = await db.getSettingDouble(_kWidth);
    final h = await db.getSettingDouble(_kHeight);
    final x = await db.getSettingDouble(_kX);
    final y = await db.getSettingDouble(_kY);
    final maxed = await db.getSettingBool(_kMaximized);
    if (w == null || h == null) return null;
    return (
      size: Size(w, h),
      position: Offset(x ?? 0, y ?? 0),
      maximized: maxed ?? false,
    );
  }

  /// 保存窗口状态（部分字段可只更新指定项）
  static Future<void> save({
    Size? size,
    Offset? position,
    bool? maximized,
  }) async {
    final db = DatabaseHelper.instance;
    if (size != null) {
      await db.setSettingDouble(_kWidth, size.width);
      await db.setSettingDouble(_kHeight, size.height);
    }
    if (position != null) {
      await db.setSettingDouble(_kX, position.dx);
      await db.setSettingDouble(_kY, position.dy);
    }
    if (maximized != null) {
      await db.setSettingBool(_kMaximized, maximized);
    }
  }
}
