import 'package:flutter/foundation.dart';
import '../models/thread_item.dart';
import '../core/logger.dart';

/// 帖子列表加载状态
enum LoadState { initial, loading, loaded, error }

/// 通用帖子列表控制器
///
/// 管理分页、刷新、内存缓存逻辑。
/// 无脑翻页：上一页/下一页始终可点击，无数据时显示空状态。
/// 通过 [fetchFn] 注入具体 API 调用，支持导读、版块、个人发帖等场景复用。
class ThreadListController extends ChangeNotifier {
  final Future<Map<String, dynamic>> Function({required int page}) fetchFn;

  List<ThreadItem> items = [];
  LoadState state = LoadState.initial;
  String? errorMessage;
  int page = 1;
  int totalPages = 0; // 仅供跳页弹窗显示，不影响翻页

  /// 内存缓存：page → items
  final Map<int, List<ThreadItem>> _pageCache = {};

  /// 最大缓存页数
  static const int _maxCachePages = 20;

  ThreadListController({required this.fetchFn});

  // ==================== 分页状态 ====================

  bool get hasPrev => page > 1;
  bool get hasNext => true; // 始终允许下一页

  // ==================== 加载 / 刷新 ====================

  /// 首次加载 / 重置加载
  Future<void> loadInitial() async {
    state = LoadState.loading;
    page = 1;
    _pageCache.clear();
    notifyListeners();

    try {
      final result = await fetchFn(page: page);
      items = _parseItems(result);
      totalPages = result['totalPages'] as int? ?? 0;
      _cachePage(1, items);
      state = LoadState.loaded;
      AppLogger.i('PAGE', 'loaded ${items.length} items');
    } catch (e) {
      errorMessage = e.toString();
      state = LoadState.error;
      AppLogger.e('PAGE', 'load failed: $e');
    }
    notifyListeners();
  }

  /// 下拉刷新：清空缓存，重新加载第一页
  Future<void> refresh() async {
    if (state == LoadState.loading) return;
    _pageCache.clear();
    page = 1;
    notifyListeners();

    try {
      final result = await fetchFn(page: 1);
      final newItems = _parseItems(result);
      items = newItems;
      totalPages = result['totalPages'] as int? ?? 0;
      _cachePage(1, newItems);
      notifyListeners();
    } catch (e) {
      debugPrint('[ThreadList] refresh error: $e');
    }
  }

  // ==================== 翻页 ====================

  /// 跳转到指定页（缓存命中直接返回，否则请求）
  Future<void> goToPage(int targetPage) async {
    if (targetPage < 1 || targetPage == page) return;

    // 缓存命中
    if (_pageCache.containsKey(targetPage)) {
      items = List.from(_pageCache[targetPage]!);
      page = targetPage;
      notifyListeners();
      return;
    }

    state = LoadState.loading;
    page = targetPage;
    notifyListeners();

    try {
      final result = await fetchFn(page: targetPage);
      final newItems = _parseItems(result);

      // 有无数据都停在此页，无数据时显示空状态（分页器仍在，可翻走）
      items = newItems;
      final tp = result['totalPages'] as int?;
      if (tp != null && tp > 0) totalPages = tp;
      if (newItems.isNotEmpty) _cachePage(targetPage, newItems);
      state = LoadState.loaded;
      notifyListeners();
    } catch (e) {
      errorMessage = e.toString();
      page = targetPage > 1 ? targetPage - 1 : 1;
      state = LoadState.error;
      notifyListeners();
    }
  }

  Future<void> nextPage() => goToPage(page + 1);
  Future<void> prevPage() => goToPage(page - 1);

  bool get hasCachedFirst => _pageCache.containsKey(1);

  // ==================== 内部 ====================

  void _cachePage(int p, List<ThreadItem> pageItems) {
    if (_pageCache.length >= _maxCachePages) {
      _pageCache.remove(_pageCache.keys.first);
    }
    _pageCache[p] = List.from(pageItems);
  }

  List<ThreadItem> _parseItems(Map<String, dynamic> result) {
    final list = result['threads'] as List<dynamic>?;
    if (list == null) return [];
    return list
        .map((j) => ThreadItem.fromJson(j as Map<String, dynamic>))
        .toList();
  }
}
