import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../api/forum/online/export.dart' as online_api;
import '../../services/api_service.dart';
import '../../core/logger.dart';
import '../../widgets/page_error_widget.dart';
import '../../widgets/user_avatar.dart';

/// 在线用户页面
///
/// 展示当前在线会员列表，支持按用户名/UID 搜索。
class OnlinePage extends StatefulWidget {
  const OnlinePage({super.key});

  @override
  State<OnlinePage> createState() => _OnlinePageState();
}

class _OnlinePageState extends State<OnlinePage> {
  final _items = <Map<String, dynamic>>[];
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isLoading = false;
  String? _error;
  String _stats = '';

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
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
      final result = await online_api.fetchOnlineUsers(ApiService().dio);
      if (!mounted) return;

      if (result['success'] != true) {
        setState(() {
          _error = result['message'] as String? ?? '加载失败';
          _isLoading = false;
        });
        return;
      }

      final items = (result['items'] as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final stats = result['stats'] as String? ?? '';

      setState(() {
        _items
          ..clear()
          ..addAll(items);
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      AppLogger.w('PAGE', 'OnlinePage error: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _onRefresh() async {
    await _fetch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('在线用户'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _onRefresh),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          if (_stats.isNotEmpty && _searchQuery.isEmpty) _buildStatsBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildStatsBar() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
      child: Text(
        _stats,
        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: '搜索用户名或 UID…',
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
    final cs = Theme.of(context).colorScheme;
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
              _searchQuery.isNotEmpty ? Icons.search_off : Icons.people_outline,
              size: 48,
              color: cs.outlineVariant,
            ),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty ? '未找到匹配结果' : '暂无数据',
              style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 每项固定宽度约 160，自适应列数
        final crossAxisCount = (constraints.maxWidth / 160).floor().clamp(1, 8);

        return GridView.builder(
          padding: const EdgeInsets.all(8),
          physics: const AlwaysScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 3.8,
          ),
          itemCount: shown.length,
          itemBuilder: (context, index) {
            final item = shown[index];
            final username = item['username'] as String? ?? '';
            final uid = item['uid'] as String? ?? '';
            final type = item['type'] as String? ?? '';
            final time = item['time'] as String? ?? '';

            final typeColor = switch (type) {
              '管理员' => cs.error,
              '超级版主' => cs.onSurfaceVariant,
              '版主' => cs.onSurfaceVariant,
              _ => cs.onSurfaceVariant,
            };

            return Card(
              margin: EdgeInsets.zero,
              elevation: 0.5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => context.push('/user/$uid'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      UserAvatar(uid: uid, nickname: username, radius: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              username,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                if (type.isNotEmpty) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 0,
                                    ),
                                    decoration: BoxDecoration(
                                      color: typeColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      type,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: typeColor,
                                        fontWeight: FontWeight.w600,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Icon(
                                  Icons.access_time,
                                  size: 10,
                                  color: cs.onSurfaceVariant,
                                ),
                                const SizedBox(width: 1),
                                Text(
                                  time,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
