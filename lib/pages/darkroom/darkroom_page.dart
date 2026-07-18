import 'package:flutter/material.dart';
import '../../api/forum/darkroom/export.dart' as darkroom_api;
import '../../services/api_service.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/page_error_widget.dart';

/// 小黑屋页面
///
/// 宽屏自适应多列布局，支持按 uid / 昵称搜索。
class DarkroomPage extends StatefulWidget {
  const DarkroomPage({super.key});

  @override
  State<DarkroomPage> createState() => _DarkroomPageState();
}

class _DarkroomPageState extends State<DarkroomPage> {
  final _scrollController = ScrollController();
  final _items = <Map<String, dynamic>>[];
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;
  bool _hasMore = true;
  String _nextCid = '';

  static const double _gap = 8;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredItems {
    if (_searchQuery.isEmpty) return _items;
    final q = _searchQuery.toLowerCase();
    return _items.where((item) {
      final username = (item['username'] as String? ?? '').toLowerCase();
      final uid = item['uid'] as String? ?? '';
      return username.contains(q) || uid.contains(q);
    }).toList();
  }

  Future<void> _fetch() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 第 1 页：不传 cid
      final result = await darkroom_api.getList(ApiService().dio);
      if (!mounted) return;

      if (result['success'] != true) {
        setState(() {
          _error = result['message'] as String? ?? '加载失败';
          _isLoading = false;
        });
        return;
      }

      var items = (result['items'] as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      var hasMore = result['hasMore'] as bool;
      var nextCid = result['nextCid'] as String;

      // 第 2 页：如果还有下一页，立即再取一页
      if (hasMore && nextCid.isNotEmpty) {
        final result2 = await darkroom_api.getList(
          ApiService().dio,
          cid: nextCid,
        );
        if (!mounted) return;

        if (result2['success'] == true) {
          final items2 = (result2['items'] as List<dynamic>)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          items.addAll(items2);
          hasMore = result2['hasMore'] as bool;
          nextCid = result2['nextCid'] as String;
        }
      }

      setState(() {
        _items
          ..clear()
          ..addAll(items);
        _hasMore = hasMore;
        _nextCid = nextCid;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _onRefresh() async {
    _nextCid = '';
    _hasMore = true;
    await _fetch();
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final result = await darkroom_api.getList(
        ApiService().dio,
        cid: _nextCid,
      );
      if (!mounted) return;

      if (result['success'] != true) {
        setState(() => _isLoadingMore = false);
        return;
      }

      final items = (result['items'] as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      setState(() {
        _items.addAll(items);
        _hasMore = result['hasMore'] as bool;
        _nextCid = result['nextCid'] as String;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('小黑屋'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _onRefresh),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: '搜索 UID 或昵称…',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onChanged: (v) => setState(() => _searchQuery = v.trim()),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return PageErrorWidget(message: _error!, onRetry: _onRefresh);
    }

    final shown = _filteredItems;

    if (shown.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _searchQuery.isNotEmpty
                  ? Icons.search_off
                  : Icons.shield_outlined,
              size: 48,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty ? '未找到匹配结果' : '暂无数据',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification) {
          final metrics = notification.metrics;
          if (metrics.maxScrollExtent > 0 &&
              metrics.pixels >= metrics.maxScrollExtent - 200 &&
              !_isLoadingMore &&
              _hasMore &&
              _searchQuery.isEmpty) {
            _loadMore();
          }
        }
        return false;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = constraints.maxWidth >= 900
              ? 3
              : constraints.maxWidth >= 600
              ? 2
              : 1;
          final cardWidth =
              (constraints.maxWidth - 12 - (crossAxisCount - 1) * _gap) /
              crossAxisCount;
          final totalShown = shown.length;
          final rows = (totalShown / crossAxisCount).ceil();

          return ListView.builder(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 12),
            itemCount: rows + (_isLoadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= rows) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }

              final start = index * crossAxisCount;
              final end = (start + crossAxisCount).clamp(0, totalShown);
              final rowItems = shown.sublist(start, end);

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (int i = 0; i < rowItems.length; i++) ...[
                      if (i > 0) SizedBox(width: _gap),
                      SizedBox(
                        width: cardWidth,
                        child: _DarkroomCard(item: rowItems[i]),
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// 小黑屋条目卡片
///
/// 布局：
/// ┌─────────────────────────────────────────┐
/// │  [头像]  爱情h            🕐 前天 22:41  │
/// │          [禁止访问]  永不过期    UID:153922 │
/// │                                          │
/// │    ┌────────────────────────────────┐    │
/// │    │ （头像）康哥                   │    │
/// │    │  引流发布黄色内容              │    │
/// │    └────────────────────────────────┘    │
/// └─────────────────────────────────────────┘
class _DarkroomCard extends StatelessWidget {
  final Map<String, dynamic> item;

  const _DarkroomCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final username = item['username'] as String? ?? '';
    final uid = item['uid'] as String? ?? '';
    final action = item['action'] as String? ?? '';
    final reason = item['reason'] as String? ?? '';
    final operator = item['operator'] as String? ?? '';
    final operatorId = item['operatorid'] as String? ?? '';
    final dateline = item['dateline'] as String? ?? '';
    final groupExpiry = item['groupexpiry'] as String? ?? '';

    final actionColor = action.contains('访问')
        ? Colors.red
        : action.contains('发言')
        ? Colors.orange
        : Colors.grey;

    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 顶部：头像跨两行居中 + 昵称/时间/标签/UID ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: UserAvatar(uid: uid, nickname: username, radius: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Row 1：昵称（左）+ 时间（右）
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              username,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            Icons.access_time,
                            size: 12,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            dateline,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      // Row 2：操作标签 + 期限（左）+ UID（右）
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: actionColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              action,
                              style: TextStyle(
                                fontSize: 11,
                                color: actionColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (groupExpiry.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Text(
                              groupExpiry,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                          const Spacer(),
                          Text(
                            'UID:$uid',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // ── 气泡：执行者信息 + 理由 ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(width: 24), // 缩进（头像宽36 + gap8 = 44）
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(10),
                        bottomLeft: Radius.circular(10),
                        bottomRight: Radius.circular(10),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: UserAvatar(
                            uid: operatorId,
                            nickname: operator,
                            radius: 10,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                operator,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                reason,
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
