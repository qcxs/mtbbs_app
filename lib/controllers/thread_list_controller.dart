import 'package:flutter/foundation.dart';
import '../models/thread_item.dart';
import '../core/logger.dart';

/// 帖子列表加载状态
enum LoadState { initial, loading, loaded, error, loadingMore }

/// 通用帖子列表控制器
///
/// 管理分页、刷新、加载更多、去重逻辑。
/// 通过 [fetchFn] 注入具体 API 调用，支持导读、版块、个人发帖等场景复用。
///
/// 使用示例：
/// ```dart
/// final ctrl = ThreadListController(
///   fetchFn: (page) => guide_api.getThreadList(dio, page: page),
/// );
/// ```
class ThreadListController extends ChangeNotifier {
  final Future<Map<String, dynamic>> Function({required int page}) fetchFn;

  List<ThreadItem> items = [];
  LoadState state = LoadState.initial;
  String? errorMessage;
  int page = 1;
  bool hasMore = true;

  ThreadListController({required this.fetchFn});

  /// 首次加载 / 重置加载
  Future<void> loadInitial() async {
    state = LoadState.loading;
    page = 1;
    notifyListeners();

    try {
      final result = await fetchFn(page: page);
      items = _parseItems(result);
      hasMore = result['hasMore'] as bool? ?? false;
      state = LoadState.loaded;
      AppLogger.i('PAGE', 'loaded ${items.length} items');
    } catch (e) {
      errorMessage = e.toString();
      state = LoadState.error;
      AppLogger.e('PAGE', 'load failed: $e');
    }
    notifyListeners();
  }

  /// 下拉刷新：清旧数据，重新加载
  Future<void> refresh() async {
    if (state == LoadState.loading || state == LoadState.loadingMore) return;

    items.clear();
    page = 1;
    notifyListeners();

    try {
      final result = await fetchFn(page: 1);
      final newItems = _parseItems(result);
      items = newItems;
      hasMore = result['hasMore'] as bool? ?? true;
      notifyListeners();
    } catch (e) {
      debugPrint('[ThreadList] refresh error: $e');
    }
  }

  /// 触底加载下一页（自动节流：loadingMore 状态防止并发）
  Future<void> loadMore() async {
    if (!hasMore ||
        state == LoadState.loading ||
        state == LoadState.loadingMore)
      return;

    state = LoadState.loadingMore;
    notifyListeners();

    page++;

    try {
      final result = await fetchFn(page: page);
      final newItems = _parseItems(result);

      if (newItems.isEmpty) {
        hasMore = false;
      } else {
        items.addAll(newItems);
        // 有数据就认为还有更多，不依赖服务端 hasMore
        hasMore = true;
      }
      state = LoadState.loaded;
      notifyListeners();
    } catch (e) {
      debugPrint('[ThreadList] loadMore error: $e');
      page--; // 回滚页码
      state = LoadState.loaded;
      notifyListeners();
    }
  }

  List<ThreadItem> _parseItems(Map<String, dynamic> result) {
    final list = result['threads'] as List<dynamic>?;
    if (list == null) return [];
    return list
        .map((j) => ThreadItem.fromJson(j as Map<String, dynamic>))
        .toList();
  }
}
