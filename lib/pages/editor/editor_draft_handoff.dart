import 'package:mtbbs/models/editor_snapshot.dart';

/// 迷你编辑器 → 完整版编辑器的**内存草稿交接**（单槽）。
///
/// 「展开为完整版」时：调用方先写快照保底（可恢复），再把草稿放入本槽；
/// 全屏 [EditorPage] 打开时按 (type, tid, pid) 匹配取出并预填正文。
///
/// 只保一个待交接草稿：同一时刻只会有一个编辑器在展开，够用且无生命周期负担。
class EditorDraftHandoff {
  EditorDraftHandoff._();

  static ({EditorType type, String tid, String pid, String content})? _pending;

  static void put({
    required EditorType type,
    required String tid,
    required String pid,
    required String content,
  }) {
    _pending = (type: type, tid: tid, pid: pid, content: content);
  }

  /// 取出与当前打开目标匹配的草稿（不匹配则保留、返回 null）
  static String? take({
    required EditorType type,
    required String tid,
    required String pid,
  }) {
    final p = _pending;
    if (p == null) return null;
    if (p.type != type || p.tid != tid || p.pid != pid) return null;
    _pending = null;
    return p.content;
  }
}
