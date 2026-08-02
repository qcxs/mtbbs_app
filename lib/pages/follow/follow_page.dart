import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/api/home/follow/export.dart' as follow_api;
import 'package:mtbbs/api/home/space/export.dart' as space_api;
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/widgets/common/user_avatar.dart';
import 'package:mtbbs/widgets/layout/page_error_widget.dart';
import 'package:mtbbs/widgets/layout/pagination_bar.dart';
import 'package:mtbbs/widgets/layout/state_views.dart';

/// 关注/粉丝列表页面（移动端命名：关注=following、粉丝=follower）
///
/// 顶部展示账号（头像 + 昵称 + UID + 用户组），下方为关注/粉丝的瀑布流
/// （列数随宽度自适应，各列高度独立），支持按用户名/UID 搜索，底部支持翻页。
class FollowPage extends StatefulWidget {
  /// 'following'（关注/我收听的人）| 'follower'（粉丝/我的听众）
  final String type;

  /// 账号 UID；空 = 当前登录用户自己的列表
  final String? uid;

  /// 初始页码（URL 路由进入时携带）
  final int initialPage;

  const FollowPage({
    super.key,
    required this.type,
    this.uid,
    this.initialPage = 1,
  });

  /// 当前是否为关注（following）页
  bool get isFollowing => type == 'following';

  @override
  State<FollowPage> createState() => _FollowPageState();
}

class _FollowPageState extends State<FollowPage> {
  final _items = <Map<String, dynamic>>[];
  final _searchController = TextEditingController();
  String _searchQuery = '';
  Map<String, dynamic>? _account;
  int _page = 1;
  int _totalPages = 1;
  bool _isLoading = false;
  String? _error;

  String get _uid => widget.uid ?? '';
  String get _title => widget.isFollowing ? '关注' : '粉丝';

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
    });
    await Future.wait([_fetchAccount(), _fetchList(widget.initialPage)]);
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
      AppLogger.w('PAGE', 'FollowPage account error: $e');
    }
  }

  Future<void> _fetchList(int page) async {
    try {
      final result = await follow_api.getFollowList(
        ApiService().dio,
        type: widget.type,
        uid: _uid,
        page: page,
      );
      if (!mounted) return;
      if (result['success'] != true) {
        setState(() {
          _error = result['message'] as String? ?? '加载失败';
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
      AppLogger.w('PAGE', 'FollowPage error: $e');
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
    _fetchList(page);
  }

  /// 打开某用户的关注/粉丝页（列表项里的“听众/收听”数字点击跳转）
  void _openUserFollow(String uid, {required bool following}) {
    if (uid.isEmpty) return;
    context.push(
      '/follow?type=${following ? 'following' : 'follower'}&uid=$uid',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
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
                      : (uid.isNotEmpty ? '用户 $uid' : _title),
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

  /// 关注/粉丝列表（Wrap 自适应：窄屏单列整行卡片，宽屏多列）
  Widget _buildBody() {
    if (_isLoading && _items.isEmpty) return const LoadingView();

    if (_error != null) {
      return PageErrorWidget(message: _error!, onRetry: _onRefresh);
    }

    if (_items.isEmpty) {
      return EmptyView(
        icon: _searchQuery.isNotEmpty ? Icons.search_off : Icons.people_outline,
        text: _searchQuery.isNotEmpty
            ? '未找到匹配结果'
            : (widget.isFollowing ? '暂无关注' : '暂无粉丝'),
      );
    }

    final shown = _filteredItems;

    // 瀑布流（SliverMasonryGrid）：每项约 240 宽自适应列数，各列按内容高度独立增长，
    // 矮卡片不会被同行高卡片撑出下方空白；窄屏单列时整行卡片铺满无空白。
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = ((constraints.maxWidth - 16) / 240).floor().clamp(1, 8);
        const spacing = 6.0;

        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(8),
              sliver: SliverMasonryGrid.count(
                crossAxisCount: cols,
                mainAxisSpacing: spacing,
                crossAxisSpacing: spacing,
                itemBuilder: (context, index) => _buildItem(shown[index]),
                childCount: shown.length,
              ),
            ),
          ],
        );
      },
    );
  }

  /// 关注/粉丝卡片
  Widget _buildItem(Map<String, dynamic> item) {
    final cs = Theme.of(context).colorScheme;
    final username = item['username'] as String? ?? '';
    final uid = item['uid'] as String? ?? '';
    final note = item['note'] as String? ?? '';
    final from = item['from'] as String? ?? '';
    final recentAction = item['recentAction'] as String? ?? '';
    final followerCount = item['followerCount'] as String? ?? '';
    final followingCount = item['followingCount'] as String? ?? '';

    // 副标题优先级：备注 > 来自 > 最近动作
    final subtitle = note.isNotEmpty
        ? note
        : (from.isNotEmpty ? '来自 $from' : recentAction);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/user/$uid'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              UserAvatar(uid: uid, nickname: username, radius: 15),
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
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (followerCount.isNotEmpty ||
                        followingCount.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (followerCount.isNotEmpty)
                            _countChip(
                              '听众',
                              followerCount,
                              following: false,
                              uid: uid,
                            ),
                          if (followingCount.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            _countChip(
                              '收听',
                              followingCount,
                              following: true,
                              uid: uid,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 听众/收听 数字徽标（点击跳转对应用户的关注/粉丝页）
  Widget _countChip(
    String label,
    String count, {
    required bool following,
    required String uid,
  }) {
    final cs = Theme.of(context).colorScheme;
    final style = TextStyle(fontSize: 10, color: cs.onSurfaceVariant);
    return InkWell(
      onTap: count.isNotEmpty
          ? () => _openUserFollow(uid, following: following)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text.rich(
          TextSpan(
            text: '$label ',
            style: style,
            children: [
              TextSpan(
                text: count,
                style: style.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
