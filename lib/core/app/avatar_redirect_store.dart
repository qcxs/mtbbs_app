import 'dart:async';
import 'dart:convert';

import 'package:mtbbs/core/utils/database_helper.dart';
import 'package:mtbbs/core/utils/logger.dart';

/// 头像 301 重定向映射的持久化存储。
///
/// 键为原始头像 URL（如 `{base}/uc_server/avatar.php?uid=1&size=middle`），
/// 值为解析后的最终 URL；值等于键表示已验证无重定向。
///
/// 磁盘缓存以「最终 URL」为 key，不持久化该映射就无法在跳过 HEAD 请求的
/// 前提下定位缓存文件。本存储让 [UserAvatar] 在缓存命中时零网络请求，
/// 仅在缓存缺失/过期时才发 HEAD 重新解析。
///
/// 持久化走统一 [DatabaseHelper]（sembast 单库），整体序列化为 JSON 存于
/// `avatar_redirects` store，内存即时生效 + 磁盘防抖批量写入。
class AvatarRedirectStore {
  AvatarRedirectStore._();
  static final AvatarRedirectStore instance = AvatarRedirectStore._();

  final Map<String, String> _map = {};
  Future<void>? _loading;
  Timer? _saveTimer;

  /// 从数据库加载映射（幂等，只加载一次）。
  Future<void> loadIfNeeded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final raw = await DatabaseHelper.instance.getAvatarRedirectsRaw();
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _map.clear();
        decoded.forEach((k, v) {
          // 值为 null（历史无重定向）归一为键本身；非字符串条目丢弃
          if (v is String) {
            _map[k] = v;
          } else if (v == null) {
            _map[k] = k;
          }
        });
      }
    } catch (e) {
      AppLogger.w('AVATAR', 'load redirect map failed: $e');
    }
  }

  /// 查询映射。
  ///
  /// 返回 `known=false` 表示从未解析过（未知）；
  /// `known=true` 时 [value] 为最终 URL（等于原始 URL 表示无重定向）。
  ({bool known, String value}) lookup(String url) {
    if (!_map.containsKey(url)) return (known: false, value: url);
    return (known: true, value: _map[url]!);
  }

  /// 记录映射并持久化（内存即时生效，磁盘防抖 1 秒批量写入）。
  void set(String url, String finalUrl) {
    _map[url] = finalUrl;
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), () => _save());
  }

  Future<void> _save() async {
    try {
      await DatabaseHelper.instance.setAvatarRedirectsRaw(jsonEncode(_map));
    } catch (e) {
      AppLogger.w('AVATAR', 'save redirect map failed: $e');
    }
  }
}
