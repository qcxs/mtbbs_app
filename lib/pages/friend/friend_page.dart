import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/api/home/friend/export.dart' as friend_api;
import 'package:mtbbs/api/home/space/export.dart' as space_api;
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/widgets/common/user_avatar.dart';
import 'package:mtbbs/widgets/layout/page_error_widget.dart';
import 'package:mtbbs/widgets/layout/pagination_bar.dart';
import 'package:mtbbs/widgets/layout/state_views.dart';

/// 好友列表页面
///
/// 顶部展示账号（头像 + 昵称 + UID + 用户组），下方为好友的自适应网格列表
/// （宽屏自动多列，类似在线用户页），支持按用户名/UID 搜索，底部支持翻页。
class FriendPage extends StatefulWidget {
  /// 账号 UID；空 = 当前登录用户自己的好友
  final String? uid;

  /// 初始页码（URL 路由进入时携带）
  final int initialPage;

  const FriendPage({super.key, this.uid, this.initialPage = 1});

  @override
  State<FriendPage> createState() => _FriendPageState();
}

class _FriendPageState extends State<FriendPage> {
  final _items = <Map<String, dynamic>>[];
  final _searchController = TextEditingController();
  String _searchQuery = '';
  Map<String, dynamic>? _account;
  int _page = 1;
  int _totalPages = 1;
  bool _isLoading = false;
  bool _privacyBlocked = false;
  String? _error;

  String get _uid => widget.uid ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 本地搜索过滤（用户名 / UID）
  List<Map<String, dynamic>> get _filteredItems {
    if (_searchQuery.isEmpty) return _items;
    final q = _searchQuery.toLowerCase();
    return _items.where((item) {
      final username = (item['username'] as String? ?? '').toLowerCase();
      final uid = item['uid'] as String? ?? '';
      return username.contains(q) || uid.contains(q);
    }).toList();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _privacyBlocked = false;
    });
    await Future.wait([_fetchAccount(), _fetchFriends(widget.initialPage)]);
  }

  /// 顶部账号资料（uid 空 = 当前登录用户）
  Future<void> _fetchAccount() async {
    if (_account != null) return;
    try {
      final result = await space_api.getUserProfile(
        ApiService().dio,
        uid: _uid,
      );
      if (!mounted) return;
      final profile = result['profile'];
      if (result['success'] == true && profile is Map) {
        setState(() => _account = Map<String, dynamic>.from(profile));
      }
    } catch (e) {
      AppLogger.w('PAGE', 'FriendPage account error: $e');
    }
  }

  Future<void> _fetchFriends(int page) async {
    try {
      final result = await friend_api.getFriendList(
        ApiService().dio,
        uid: _uid,
        page: page,
      );
      if (!mounted) return;
      if (result['success'] != true) {
        final privacy = result['privacyBlocked'] == true;
        setState(() {
          _privacyBlocked = privacy;
          _error =
              result['message'] as String? ?? (privacy ? '无权查看该用户的好友' : '加载失败');
          _isLoading = false;
        });
        return;
      }
      setState(() {
        _items
          ..clear()
          ..addAll(
            (result['items'] as List<dynamic>).map(
              (e) => Map<String, dynamic>.from(e as Map),
            ),
          );
        _page = (result['currentPage'] as num?)?.toInt() ?? page;
        _totalPages = (result['totalPages'] as num?)?.toInt() ?? 1;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      AppLogger.w('PAGE', 'FriendPage error: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _onRefresh() async {
    setState(() {
      _account = null;
      _items.clear();
    });
    await _load();
  }

  void _goToPage(int page) {
    if (page == _page) return;
    setState(() => _isLoading = true);
    _fetchFriends(page);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('好友'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _onRefresh),
        ],
      ),
      body: Column(
        children: [
          _buildAccountHeader(),
          _buildSearchBar(),
          Expanded(child: _buildBody()),
          if (_totalPages > 1 && !_isLoading && _error == null)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                child: PaginationBar(
                  page: _page,
                  totalPages: _totalPages,
                  onGoToPage: _goToPage,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 搜索框：本地过滤用户名 / UID
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
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

  /// 顶部账号卡片
  Widget _buildAccountHeader() {
    final cs = Theme.of(context).colorScheme;
    final profile = _account;
    final nickname = profile?['nickname'] as String? ?? '';
    final uid = profile?['uid'] as String? ?? _uid;
    final activity = profile?['activity'];
    final userGroup = activity is Map
        ? (activity['userGroup'] as String? ?? '')
        : '';
    final online = profile?['online'] == true;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: cs.surfaceContainerLow,
      child: Row(
        children: [
          UserAvatar(
            uid: uid,
            nickname: nickname,
            radius: 26,
            tapAction: AvatarTapAction.none,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nickname.isNotEmpty
                      ? nickname
                      : (uid.isNotEmpty ? '用户 $uid' : '好友'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (uid.isNotEmpty)
                      Text(
                        'UID: $uid',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    if (uid.isNotEmpty && userGroup.isNotEmpty) ...[
                      Text(
                        ' · ',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        userGroup,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (online) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.circle, size: 8, color: cs.primary),
                      const SizedBox(width: 2),
                      Text(
                        '在线',
                        style: TextStyle(fontSize: 12, color: cs.primary),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 好友列表（自适应网格，宽屏多列）
  Widget _buildBody() {
    final cs = Theme.of(context).colorScheme;

    if (_isLoading && _items.isEmpty) return const LoadingView();

    if (_error != null) {
      return PageErrorWidget(
        message: _error!,
        // 隐私受限时重试无意义，仅提供返回
        onRetry: _privacyBlocked ? null : _onRefresh,
      );
    }

    if (_items.isEmpty) {
      return EmptyView(
        icon: _searchQuery.isNotEmpty ? Icons.search_off : Icons.people_outline,
        text: _searchQuery.isNotEmpty ? '未找到匹配结果' : '暂无好友',
      );
    }

    final shown = _filteredItems;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 每项固定宽度约 160，自适应列数（同在线用户页）
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
            final userGroup = item['userGroup'] as String? ?? '';
            final credits = item['credits'] as String? ?? '';
            final note = item['note'] as String? ?? '';
            final hot = item['hot'] as String? ?? '';

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
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    username,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (hot.isNotEmpty) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.local_fire_department,
                                    size: 11,
                                    color: cs.error,
                                  ),
                                  Text(
                                    hot,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: cs.error,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            if (userGroup.isNotEmpty)
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 0,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cs.onSurfaceVariant.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      userGroup,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: cs.onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                  if (credits.isNotEmpty) ...[
                                    const SizedBox(width: 4),
                                    Text(
                                      '积分 $credits',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ],
                              )
                            else if (note.isNotEmpty)
                              Text(
                                note,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: cs.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
