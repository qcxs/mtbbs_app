import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/api/forum/online/export.dart' as online_api;
import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/core/app/site_session.dart';
import 'package:mtbbs/core/app/site_scope.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/widgets/common/filter_search_field.dart';
import 'package:mtbbs/widgets/common/page_actions.dart';
import 'package:mtbbs/widgets/layout/page_error_widget.dart';
import 'package:mtbbs/widgets/layout/state_views.dart';
import 'package:mtbbs/widgets/common/user_avatar.dart';

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

  /// 页面作用域会话（跨站点打开时 = 目标站默认账号/游客，只读）
  SiteSession _session = const GlobalSiteSession();
  Dio get _dio => _session.dio;
  bool _sessionBound = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session = SiteScope.of(context);
    if (_sessionBound) return;
    _sessionBound = true;
    _fetch();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredItems =>
      filterUserItems(_items, _searchQuery);

  Future<void> _fetch() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await online_api.fetchOnlineUsers(_dio);
      if (!mounted) return;

      final err = apiErrorText(result);
      if (err != null) {
        setState(() {
          _error = err;
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
          PageActions(
            url: '${_session.baseUrl}/forum.php?showoldetails=yes',
            onRefresh: _onRefresh,
            loading: _isLoading,
            copyLabel: '复制在线列表链接',
          ),
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

  Widget _buildSearchBar() => FilterSearchField(
    controller: _searchController,
    query: _searchQuery,
    onChanged: (v) => setState(() => _searchQuery = v),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
  );

  Widget _buildBody() {
    final cs = Theme.of(context).colorScheme;
    if (_isLoading) return const LoadingView();

    if (_error != null) {
      return PageErrorWidget(message: _error!, onRetry: _onRefresh);
    }

    final shown = _filteredItems;

    if (shown.isEmpty) {
      return EmptyView(
        icon: _searchQuery.isNotEmpty ? Icons.search_off : Icons.people_outline,
        text: _searchQuery.isNotEmpty ? '未找到匹配结果' : '暂无数据',
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
              // 管理员是身份标识，用 primary；不用 error（非错误语义）
              '管理员' => cs.primary,
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
