import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mtbbs/core/site_store.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/api/home/smiley/export.dart' as smiley_api;
import 'package:mtbbs/core/smilie_map.dart';

/// 按站点隔离的表情服务
///
/// 每个站点的表情数据独立存储，切换站点时自动切换：
/// - [map]: insertText → imageUrl（BBCode 预览用）
/// - [smilieIdMap]: smilieId → insertText（HTML→BBCode 转换用）
/// - [groups]: 分组列表（表情选择器 UI 用）
/// - [frequentlyUsed]: 当前站点的常用表情列表
class EmojiService {
  static final EmojiService _instance = EmojiService._();
  factory EmojiService() => _instance;
  EmojiService._();

  static const int _maxFrequent = 30;

  /// 按站点 host 隔离的表情数据
  final Map<String, _SiteEmojiData> _siteData = {};

  String get _host => SiteStore.instance.host;
  _SiteEmojiData get _current =>
      _siteData.putIfAbsent(_host, () => _SiteEmojiData());

  /// insertText → imageUrl（如 "[呵呵]" → "https://..."）
  Map<String, String> get map => _current.map;

  /// smilieId → insertText（如 "1240" → "[呵呵]"）
  Map<String, String> get smilieIdMap => _current.smilieIdMap;

  /// 全部分组数据
  List<Map<String, dynamic>> get groups => _current.groups;

  /// 当前站点是否已加载
  bool get isLoaded => _current.loaded;

  /// 从 API 加载当前站点的表情数据。
  /// 优先从本地缓存恢复，缓存不存在才请求 API。
  Future<void> load() async {
    if (_current.loaded) return;
    if (await _loadFromCache()) return;
    await _fetch();
  }

  /// 强制刷新当前站点的表情数据（重新获取 API）
  Future<void> refresh() async {
    _current.reset();
    await _fetch();
  }

  // ==================== 常用表情 ====================

  /// 获取当前站点的常用表情列表（按使用次数降序，最多 30 个）
  /// 自动跳过当前站点中已不存在的表情。
  List<Map<String, dynamic>> get frequentlyUsed {
    final data = _current;
    final idMap = data.smilieIdMap;
    final entries = data.usageCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final result = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final e in entries) {
      if (result.length >= _maxFrequent) break;
      final smilieId = e.key;
      if (!idMap.containsKey(smilieId)) continue; // 跳过已不存在的表情
      if (seen.contains(smilieId)) continue;
      seen.add(smilieId);
      // 从 groups 中找到对应的 emoji 数据
      for (final g in data.groups) {
        final emojis = g['emojis'] as List<dynamic>?;
        if (emojis == null) continue;
        for (final em in emojis) {
          final emMap = em as Map<String, dynamic>;
          if (emMap['smilieId'] == smilieId) {
            result.add(emMap);
            break;
          }
        }
      }
    }
    return result;
  }

  /// 记录一次表情使用
  void recordUsage(String smilieId) {
    final data = _current;
    data.usageCount.update(smilieId, (v) => v + 1, ifAbsent: () => 1);
    _saveUsage();
  }

  Future<void> _saveUsage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      prefs.setString('emoji_usage_$_host', jsonEncode(_current.usageCount));
    } catch (_) {}
  }

  Future<void> _loadUsage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('emoji_usage_$_host');
      if (json != null && json.isNotEmpty) {
        final decoded = jsonDecode(json) as Map<String, dynamic>;
        _current.usageCount = decoded.map(
          (k, v) => MapEntry(k, (v as num).toInt()),
        );
      }
    } catch (_) {}
  }

  // ==================== 持久化缓存 ====================

  String get _cacheKey => 'smilie_data_$_host';

  /// 从 SharedPreferences 恢复缓存，返回是否成功。
  /// 若 CDN 配置已变更则丢弃缓存，触发重新请求。
  Future<bool> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_cacheKey);
      if (json == null || json.isEmpty) return false;
      final data = jsonDecode(json) as Map<String, dynamic>;
      // CDN 配置变更时丢弃旧缓存
      if (data['cdnUrl']?.toString() != SiteStore.instance.cdnUrl) return false;
      _current.map = Map<String, String>.from(data['map'] as Map? ?? {});
      _current.smilieIdMap = Map<String, String>.from(
        data['smilieIdMap'] as Map? ?? {},
      );
      _current.groups = List<Map<String, dynamic>>.from(
        data['groups'] as List? ?? [],
      );
      _current.loaded = true;
      SmilieMap.update(_current.smilieIdMap);
      await _loadUsage();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 将当前表情数据持久化到 SharedPreferences
  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode({
          'cdnUrl': SiteStore.instance.cdnUrl,
          'map': _current.map,
          'smilieIdMap': _current.smilieIdMap,
          'groups': _current.groups,
        }),
      );
    } catch (_) {}
  }

  // ==================== 清空缓存 ====================

  /// 清空当前站点的表情元数据缓存（SharedPreferences + 内存）
  /// 下次调用 [load] 时会重新从 API 获取。
  Future<void> clearCache() async {
    _current.reset();
    SmilieMap.update({});
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove('emoji_usage_$_host');
    } catch (_) {}
  }

  // ==================== 内部 ====================

  Future<void> _fetch() async {
    try {
      final result = await smiley_api.fetchSmilies(ApiService().dio);
      if (result['success'] == true) {
        _current.groups = List<Map<String, dynamic>>.from(
          result['groups'] as List,
        );
        _current.smilieIdMap = Map<String, String>.from(
          result['smilieIdMap'] as Map,
        );
        _current.map = Map<String, String>.from(result['insertTextMap'] as Map);
        _current.loaded = true;
        SmilieMap.update(_current.smilieIdMap);
        await _save();
        await _loadUsage();
      }
    } catch (_) {
      // 加载失败，下次调用 load() 会重试
    }
  }
}

/// 单个站点的表情数据
class _SiteEmojiData {
  Map<String, String> map = {};
  Map<String, String> smilieIdMap = {};
  List<Map<String, dynamic>> groups = [];
  bool loaded = false;

  /// smilieId → 使用次数
  Map<String, int> usageCount = {};

  void reset() {
    map = {};
    smilieIdMap = {};
    groups = [];
    usageCount = {};
    loaded = false;
  }
}
