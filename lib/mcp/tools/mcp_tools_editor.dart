import 'package:mcp_dart/mcp_dart.dart';
import 'package:mtbbs/core/utils/database_helper.dart';
import 'package:mtbbs/mcp/mcp_sanitizer.dart';
import 'package:mtbbs/mcp/mcp_types.dart';
import 'package:mtbbs/mcp/tools/mcp_payloads.dart';
import 'package:mtbbs/mcp/tools/mcp_tool_definition.dart';
import 'package:mtbbs/models/editor_snapshot.dart';

/// 只读编辑器草稿工具（`McpToolGroup.editorRead`）
///
/// 数据来自 `DatabaseHelper` 里的编辑器快照表（App 自动保存的草稿）。
/// 只读，不会修改或发送任何内容；正文会截断。
List<McpToolDefinition> editorTools() => [
  McpToolDefinition(
    name: 'list_editor_sessions',
    group: McpToolGroup.editorRead,
    description:
        '列出编辑器里正在写的内容（发帖/回复/评论草稿会话）。快照由 App 自动保存，'
        '最近一次可能滞后数十秒。仅读取，不会修改或发送任何内容。',
    properties: const {},
    network: false, // 读本地数据库里的草稿快照
    run: (args) async {
      final sessions = await _editorSessions();
      return {'count': sessions.length, 'sessions': sessions};
    },
  ),
  McpToolDefinition(
    name: 'get_editor_draft',
    group: McpToolGroup.editorRead,
    description:
        '读取某个编辑器会话的正文（默认取最新一次快照）。session_key 来自 list_editor_sessions。'
        '正文默认返回**精简 BBCode**（已剔除纯样式标签，便于直接阅读成稿）；'
        '需要逐字原文时传 full_bbcode=true。',
    properties: {
      'session_key': JsonSchema.string(
        description: '会话标识，来自 list_editor_sessions',
      ),
      'snapshot_id': JsonSchema.string(description: '指定快照 ID；留空则取该会话最新快照'),
      'full_bbcode': JsonSchema.boolean(
        description: '是否返回完整 BBCode（含样式标签）。默认 false，精简版更省上下文。',
      ),
    },
    requiredArgs: const ['session_key'],
    network: false, // 读本地数据库里的草稿快照
    run: (args) async {
      final sessionKey = McpArgs.requireStr(args, 'session_key');
      final snapshotId = McpArgs.str(args, 'snapshot_id');
      final fullBbcode = McpArgs.boolean(args, 'full_bbcode');
      final db = DatabaseHelper.instance;

      EditorSnapshot? snapshot;
      if (snapshotId.isNotEmpty) {
        snapshot = await db.getSnapshotById(snapshotId);
      } else {
        final list = await db.getSnapshotsBySession(sessionKey);
        snapshot = list.isEmpty ? null : list.first;
      }
      if (snapshot == null) {
        return {'found': false, 'sessionKey': sessionKey};
      }
      return {
        'found': true,
        'sessionKey': snapshot.sessionKey,
        'snapshotId': snapshot.id,
        'label': snapshot.label,
        'editorType': snapshot.editorType,
        'title': snapshot.title,
        'content': McpSanitizer.clampText(
          McpPayloads.bbcodeForAi(snapshot.content, full: fullBbcode),
          McpPayloads.maxBbcodeChars * 2,
        ),
        'wordCount': snapshot.wordCount,
        'isManual': snapshot.isManual,
        'tid': snapshot.tid,
        'pid': snapshot.pid,
        'fid': snapshot.fid,
        'createdAt': snapshot.createdAt.toIso8601String(),
      };
    },
  ),
];

/// 按会话汇总草稿：每个 sessionKey 只保留最新一次快照的摘要，按更新时间倒序
Future<List<Map<String, dynamic>>> _editorSessions() async {
  final db = DatabaseHelper.instance;
  final keys = await db.getAllSessionKeys();
  final sessions = <Map<String, dynamic>>[];

  for (final key in keys) {
    final snapshots = await db.getSnapshotsBySession(key);
    if (snapshots.isEmpty) continue;
    final latest = snapshots.first;
    sessions.add({
      'sessionKey': key,
      'label': latest.label,
      'editorType': latest.editorType,
      'tid': latest.tid,
      'pid': latest.pid,
      'fid': latest.fid,
      'title': latest.title,
      'wordCount': latest.wordCount,
      'snapshotCount': snapshots.length,
      'lastUpdated': latest.createdAt.toIso8601String(),
    });
  }

  sessions.sort(
    (a, b) =>
        (b['lastUpdated'] as String).compareTo(a['lastUpdated'] as String),
  );
  return sessions;
}
