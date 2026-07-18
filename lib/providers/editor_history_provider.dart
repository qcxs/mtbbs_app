import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mtbbs/models/editor_snapshot.dart';

// ==================== 会话摘要 ====================

/// 编辑器会话摘要（用于历史记录页列表展示）
class EditorSessionSummary {
  final String key;
  final String label;
  final int totalCount;
  final int manualCount;
  final int totalImages;
  final DateTime lastUpdated;

  const EditorSessionSummary({
    required this.key,
    required this.label,
    required this.totalCount,
    required this.manualCount,
    required this.totalImages,
    required this.lastUpdated,
  });
}

// ==================== Provider ====================

/// 编辑器历史记录管理
class EditorHistoryProvider extends ChangeNotifier {
  static const String _storageKey = 'editor_history';

  static const int defaultMaxAutoSnapshots = 10;
  static const Duration defaultAutoSaveInterval = Duration(seconds: 30);
  static const int defaultMinSnapshotWordCount = 10;

  int maxAutoSnapshots = defaultMaxAutoSnapshots;
  Duration autoSaveInterval = defaultAutoSaveInterval;

  /// 最短字数过滤：字数太少不保存，丢了也不心疼
  int minSnapshotWordCount = defaultMinSnapshotWordCount;

  final Map<String, List<EditorSnapshot>> _autoMap = {};
  final Map<String, List<EditorSnapshot>> _manualMap = {};
  final Set<String> _submittedKeys = {};
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    await _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        _autoMap.clear();
        _manualMap.clear();
        _submittedKeys.clear();

        final autoRaw = data['auto'] as Map<String, dynamic>? ?? {};
        final manualRaw = data['manual'] as Map<String, dynamic>? ?? {};
        final submittedRaw = data['submitted'] as List<dynamic>? ?? [];

        for (final entry in autoRaw.entries) {
          final list = (entry.value as List<dynamic>)
              .map((e) => EditorSnapshot.fromJson(e as Map<String, dynamic>))
              .toList();
          _autoMap[entry.key] = list;
        }
        for (final entry in manualRaw.entries) {
          final list = (entry.value as List<dynamic>)
              .map((e) => EditorSnapshot.fromJson(e as Map<String, dynamic>))
              .toList();
          _manualMap[entry.key] = list;
        }
        for (final k in submittedRaw) {
          _submittedKeys.add(k.toString());
        }
      }
    } catch (_) {
      _autoMap.clear();
      _manualMap.clear();
      _submittedKeys.clear();
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'auto': _autoMap.map(
          (k, v) => MapEntry(k, v.map((e) => e.toJson()).toList()),
        ),
        'manual': _manualMap.map(
          (k, v) => MapEntry(k, v.map((e) => e.toJson()).toList()),
        ),
        'submitted': _submittedKeys.toList(),
      };
      await prefs.setString(_storageKey, jsonEncode(data));
    } catch (_) {}
  }

  /// 检查快照字数是否达标
  bool _isValidSnapshot(EditorSnapshot s) =>
      s.wordCount >= minSnapshotWordCount;

  // ==================== Key 生成 ====================

  static String generateKey(
    EditorType type, {
    String tid = '',
    String pid = '',
  }) {
    switch (type) {
      case EditorType.post:
        final r = Random().nextInt(999999);
        final ts = DateTime.now().millisecondsSinceEpoch;
        return 'post_${ts}_$r';
      case EditorType.comment:
        return 'comment_$tid';
      case EditorType.reply:
        return 'reply_${tid}_$pid';
      case EditorType.editPost:
        return 'editPost_${tid}_$pid';
      case EditorType.editReply:
        return 'editReply_${tid}_$pid';
    }
  }

  // ==================== 查询 ====================

  List<EditorSnapshot> getAutoSnapshots(String key) {
    return List.unmodifiable(_autoMap[key] ?? []);
  }

  List<EditorSnapshot> getManualSnapshots(String key) {
    return List.unmodifiable(_manualMap[key] ?? []);
  }

  List<EditorSnapshot> getAllSnapshots(String key) {
    final result = [...?_autoMap[key], ...?_manualMap[key]];
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  /// 在所有会话中按 ID 查找快照（跨 key 搜索）
  EditorSnapshot? getSnapshotById(String snapshotId) {
    for (final list in _autoMap.values) {
      final found = list.where((s) => s.id == snapshotId).firstOrNull;
      if (found != null) return found;
    }
    for (final list in _manualMap.values) {
      final found = list.where((s) => s.id == snapshotId).firstOrNull;
      if (found != null) return found;
    }
    return null;
  }

  int autoCount(String key) => _autoMap[key]?.length ?? 0;

  bool hasSession(String key) {
    if (_submittedKeys.contains(key)) return false;
    return (_autoMap[key]?.isNotEmpty == true) ||
        (_manualMap[key]?.isNotEmpty == true);
  }

  Future<void> markSubmitted(String key) async {
    await _ensureLoaded();
    _submittedKeys.add(key);
    await _persist();
    notifyListeners();
  }

  /// 构建会话摘要 label：取最新一条快照（手动优先）+
  /// 图片x张 + 文字x字
  String _buildSessionLabel(String key) {
    final manuals = _manualMap[key] ?? [];
    final autos = _autoMap[key] ?? [];
    final latest = manuals.isNotEmpty
        ? manuals.last
        : autos.isNotEmpty
        ? autos.last
        : null;
    if (latest == null) return '(空)';

    final parts = <String>[];
    final preview = latest.preview;
    if (preview.isNotEmpty) {
      parts.add(
        preview.length > 30 ? '${preview.substring(0, 30)}...' : preview,
      );
    }
    if (latest.pendingAids.isNotEmpty) {
      parts.add('${latest.pendingAids.length}张图片');
    }
    parts.add('${latest.wordCount}字');
    return parts.join(' · ');
  }

  Future<List<EditorSessionSummary>> getAllSessions() async {
    await _ensureLoaded();
    final keys = <String>{..._autoMap.keys, ..._manualMap.keys};
    final result = <EditorSessionSummary>[];
    for (final key in keys) {
      final all = getAllSnapshots(key);
      if (all.isEmpty) continue;
      final manuals = _manualMap[key] ?? [];
      // 计算总图片数
      final totalImages = all.fold<int>(
        0,
        (sum, s) => sum + s.pendingAids.length,
      );
      result.add(
        EditorSessionSummary(
          key: key,
          label: _buildSessionLabel(key),
          totalCount: all.length,
          manualCount: manuals.length,
          totalImages: totalImages,
          lastUpdated: all.first.createdAt,
        ),
      );
    }
    result.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
    return result;
  }

  // ==================== 写入 ====================

  /// 添加自动快照（字数过滤 + 去重 + 上限淘汰）
  Future<void> addAutoSnapshot(EditorSnapshot snapshot) async {
    if (!_isValidSnapshot(snapshot)) return;
    await _ensureLoaded();
    final list = _autoMap.putIfAbsent(snapshot.sessionKey, () => []);
    if (list.isNotEmpty) {
      final last = list.last;
      if (last.title == snapshot.title && last.content == snapshot.content) {
        return;
      }
    }
    list.add(snapshot);
    while (list.length > maxAutoSnapshots) {
      list.removeAt(0);
    }
    await _persist();
    notifyListeners();
  }

  /// 手动保存 — 每个 key 只保留最新一条，重复保存覆盖
  ///
  /// 手动保存不受字数过滤限制，即使标题/内容为空也保存。
  Future<void> addManualSnapshot(EditorSnapshot snapshot) async {
    await _ensureLoaded();
    _manualMap[snapshot.sessionKey] = [snapshot]; // 替换为单条
    await _persist();
    notifyListeners();
  }

  Future<void> deleteSnapshot(String snapshotId) async {
    await _ensureLoaded();
    bool changed = false;
    for (final entry in _autoMap.entries) {
      entry.value.removeWhere((s) => s.id == snapshotId);
      if (entry.value.isEmpty) {
        _autoMap.remove(entry.key);
      }
      changed = true;
    }
    for (final entry in _manualMap.entries) {
      entry.value.removeWhere((s) => s.id == snapshotId);
      if (entry.value.isEmpty) {
        _manualMap.remove(entry.key);
      }
      changed = true;
    }
    if (changed) {
      await _persist();
      notifyListeners();
    }
  }

  Future<void> deleteSession(String key) async {
    await _ensureLoaded();
    _autoMap.remove(key);
    _manualMap.remove(key);
    _submittedKeys.remove(key);
    await _persist();
    notifyListeners();
  }

  Future<void> cleanup() async {
    await _ensureLoaded();
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    bool changed = false;

    void clean(Map<String, List<EditorSnapshot>> map) {
      final toRemove = <String>[];
      for (final entry in map.entries) {
        entry.value.removeWhere((s) => s.createdAt.isBefore(cutoff));
        if (entry.value.isEmpty) {
          toRemove.add(entry.key);
        }
      }
      for (final key in toRemove) {
        map.remove(key);
      }
      if (toRemove.isNotEmpty || map.values.any((l) => l.isEmpty)) {
        changed = true;
      }
    }

    clean(_autoMap);
    clean(_manualMap);
    if (changed) {
      await _persist();
      notifyListeners();
    }
  }
}
