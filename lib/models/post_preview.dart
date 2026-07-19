import 'dart:collection';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mtbbs/api/forum/viewthread/viewpid/export.dart' as viewpid_api;
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/core/logger.dart';

/// 帖子预览数据
class PostPreviewData {
  final String tid;
  final String pid;
  final String bbcode;

  const PostPreviewData({
    required this.tid,
    required this.pid,
    required this.bbcode,
  });

  Map<String, dynamic> toJson() => {'tid': tid, 'pid': pid, 'bbcode': bbcode};

  factory PostPreviewData.fromJson(Map<String, dynamic> json) {
    return PostPreviewData(
      tid: json['tid'] as String? ?? '',
      pid: json['pid'] as String? ?? '',
      bbcode: json['bbcode'] as String? ?? '',
    );
  }
}

/// 帖子预览缓存（FIFO，最多 100 条）
///
/// 内存 + SharedPreferences 双重存储：
/// - 内存中 LinkedHashMap 保持插入顺序，O(1) 访问
/// - 每次写入后异步持久化到本地
/// - 启动时从本地恢复缓存
class PostPreviewCache {
  static const int _maxSize = 100;
  static const String _storageKey = 'post_preview_cache';

  final LinkedHashMap<String, PostPreviewData> _cache = LinkedHashMap();
  bool _loaded = false;

  int get size => _cache.length;

  /// 从本地存储加载缓存
  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final list = jsonDecode(jsonStr) as List<dynamic>;
        for (final entry in list) {
          final data = PostPreviewData.fromJson(entry as Map<String, dynamic>);
          final key = '${data.tid}_${data.pid}';
          _cache[key] = data;
        }
        AppLogger.i('CACHE', 'loaded ${_cache.length} previews from disk');
      }
    } catch (_) {
      _cache.clear();
    }
    _loaded = true;
  }

  /// 持久化到本地存储
  Future<void> _persist() async {
    try {
      final list = _cache.values.map((e) => e.toJson()).toList();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(list));
    } catch (_) {}
  }

  PostPreviewData? get(String tid, String pid) {
    return _cache['${tid}_$pid'];
  }

  Future<void> put(String tid, String pid, PostPreviewData data) async {
    await _ensureLoaded();
    final key = '${tid}_$pid';
    _cache[key] = data;
    if (_cache.length > _maxSize) {
      _cache.remove(_cache.keys.first);
    }
    await _persist();
  }
}

/// 帖子预览管理器（单例）
class PostPreviewManager {
  PostPreviewManager._();
  static final PostPreviewManager instance = PostPreviewManager._();

  final PostPreviewCache _cache = PostPreviewCache();
  final Set<String> _pending = {};
  bool _inited = false;

  /// 应用启动时调用，从磁盘加载缓存，避免首次访问都走网络
  Future<void> init() async {
    if (_inited) return;
    await _cache._ensureLoaded();
    _inited = true;
  }

  /// 从持久缓存中获取（不发请求）
  PostPreviewData? getCached(String tid, String pid) => _cache.get(tid, pid);

  /// 获取预览：优先缓存，未命中则发起请求
  Future<PostPreviewData?> fetch(String tid, String pid) async {
    // 1. 查缓存
    final cached = _cache.get(tid, pid);
    if (cached != null) return cached;

    final key = '${tid}_$pid';
    if (_pending.contains(key)) return null;
    _pending.add(key);

    try {
      final result = await viewpid_api.getPostByPid(
        ApiService().dio,
        tid: tid,
        viewpid: pid,
      );
      if (result['success'] == true && result['post'] != null) {
        final post = result['post'] as Map<String, dynamic>;
        final bbcode = post['bbcode'] as String? ?? '';
        final data = PostPreviewData(tid: tid, pid: pid, bbcode: bbcode);
        await _cache.put(tid, pid, data);
        return data;
      }
      AppLogger.w(
        'PREVIEW',
        'fetch post $tid/$pid failed: ${result['message']}',
      );
      return null;
    } catch (e) {
      AppLogger.w('PREVIEW', 'fetch post $tid/$pid error: $e');
      return null;
    } finally {
      _pending.remove(key);
    }
  }
}

/// 从 viewUrl 中提取 tid/ptid 和 pid
({String tid, String pid})? parseViewUrl(String url) {
  final tidMatch = RegExp(r'[?&]ptid=(\d+)').firstMatch(url);
  final pidMatch = RegExp(r'[?&]pid=(\d+)').firstMatch(url);
  if (tidMatch != null && pidMatch != null) {
    return (tid: tidMatch.group(1)!, pid: pidMatch.group(1)!);
  }
  return null;
}
