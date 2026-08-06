import 'dart:collection';
import 'package:mtbbs/core/utils/database_helper.dart';
import 'package:mtbbs/api/forum/viewthread/viewpid/export.dart' as viewpid_api;
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/core/app/stagger_queue.dart';
import 'package:mtbbs/core/app/emoji_loader.dart';

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
/// 内存 + SQLite 双重存储：
/// - 内存中 LinkedHashMap 保持插入顺序，O(1) 访问
/// - 每次写入后增量持久化到 SQLite
/// - 启动时从 SQLite 恢复缓存
class PostPreviewCache {
  static const int _maxSize = 100;

  final LinkedHashMap<String, PostPreviewData> _cache = LinkedHashMap();
  bool _loaded = false;

  int get size => _cache.length;

  /// 从 SQLite 加载缓存
  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      _cache.clear();
      final rows = await DatabaseHelper.instance.getAllPreviewCache();
      for (final row in rows) {
        final key = '${row['tid']}_${row['pid']}';
        _cache[key] = PostPreviewData(
          tid: row['tid'] as String,
          pid: row['pid'] as String,
          bbcode: row['bbcode'] as String,
        );
      }
      AppLogger.i('CACHE', 'loaded ${_cache.length} previews');
    } catch (_) {
      _cache.clear();
    }
    _loaded = true;
  }

  PostPreviewData? get(String tid, String pid) {
    return _cache['${tid}_$pid'];
  }

  Future<void> put(String tid, String pid, PostPreviewData data) async {
    await _ensureLoaded();
    final key = '${tid}_$pid';
    _cache[key] = data;

    // 增量写入 SQLite
    await DatabaseHelper.instance.upsertPreviewCache(tid, pid, data.bbcode);

    // FIFO 淘汰：内存与 DB 同步移除最旧条目，保持双端一致
    if (_cache.length > _maxSize) {
      final removedKey = _cache.keys.first;
      _cache.remove(removedKey);
      await DatabaseHelper.instance.deletePreviewCache(removedKey);
    }
  }

  /// 清空所有帖子预览缓存
  Future<void> clear() async {
    _cache.clear();
    await DatabaseHelper.instance.clearPreviewCache();
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
      // 错峰等待放行后再发起 HTTP 请求
      await enqueueStagger().ready;

      // 确保表情已加载：解析层（Html2BBCode）从 EmojiService 读取当前
      // 站点表情数据，未加载时表情会被静默跳过，渲染层无米下锅
      await EmojiService().load();

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

  /// 清空所有帖子预览缓存
  Future<void> clear() => _cache.clear();
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
