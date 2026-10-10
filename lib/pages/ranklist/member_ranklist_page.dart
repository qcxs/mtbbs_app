import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/api/forum/ranklist/export.dart' as ranklist_api;
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/widgets/common/page_actions.dart';
import 'package:mtbbs/widgets/common/user_avatar.dart';
import 'package:mtbbs/widgets/layout/page_error_widget.dart';
import 'package:mtbbs/widgets/layout/state_views.dart';

/// 用户排行榜页（`misc.php?mod=ranklist&type=member`）
///
/// 顶部横向切换 7 个子榜（美女/帅哥/积分/好友数/邀请/发帖数/在线时间），
/// 每个子榜固定 Top 20（站点无分页）。数据按子榜懒加载并缓存。
class MemberRanklistPage extends StatefulWidget {
  const MemberRanklistPage({super.key, this.initialView = 'beauty'});

  /// 初始子榜（来自路由 `?view=`），非法值回退到第一个
  final String initialView;

  @override
  State<MemberRanklistPage> createState() => _MemberRanklistPageState();
}

/// 子榜：`id` 与站点 `view` 参数一一对应；`label` 为展示名
const _kViews = <({String id, String label})>[
  (id: 'beauty', label: '美女'),
  (id: 'handsome', label: '帅哥'),
  (id: 'credit', label: '积分'),
  (id: 'friendnum', label: '好友数'),
  (id: 'invite', label: '邀请'),
  (id: 'post', label: '发帖'),
  (id: 'onlinetime', label: '在线时间'),
];

class _MemberRanklistPageState extends State<MemberRanklistPage> {
  late int _tabIndex;
  final _items = <String, List<Map<String, dynamic>>>{};
  final _loading = <String, bool>{};
  final _errors = <String, String?>{};

  @override
  void initState() {
    super.initState();
    final idx = _kViews.indexWhere((v) => v.id == widget.initialView);
    _tabIndex = idx < 0 ? 0 : idx;
    _fetch(_kViews[_tabIndex].id);
  }

  String get _currentView => _kViews[_tabIndex].id;

  Future<void> _fetch(String view, {bool force = false}) async {
    if ((_items.containsKey(view) || _loading[view] == true) && !force) return;
    setState(() {
      _loading[view] = true;
      _errors[view] = null;
    });
    try {
      final result = await ranklist_api.getMemberRanklist(
        ApiService().dio,
        view: view,
      );
      if (!mounted) return;
      if (result['success'] == true) {
        setState(() {
          _items[view] = (result['items'] as List<dynamic>)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _loading[view] = false;
        });
      } else {
        setState(() {
          _errors[view] = result['message']?.toString() ?? '获取排行失败';
          _loading[view] = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errors[view] = e.toString();
        _loading[view] = false;
      });
    }
  }

  void _onTabChanged(int index) {
    if (index == _tabIndex) return;
    setState(() => _tabIndex = index);
    _fetch(_kViews[index].id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('用户排行'),
        actions: [
          PageActions(
            url:
                '${SiteStore.instance.baseUrl}/misc.php?mod=ranklist&type=member&view=$_currentView',
            onRefresh: () => _fetch(_currentView, force: true),
            loading: _loading[_currentView] ?? false,
            copyLabel: '复制排行榜链接',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildTabs(),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _kViews.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final isActive = i == _tabIndex;
          return GestureDetector(
            onTap: () => _onTabChanged(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isActive ? cs.primary : cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: Text(
                _kViews[i].label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  color: isActive ? cs.onPrimary : cs.onSurfaceVariant,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildList() {
    final view = _currentView;
    final loading = _loading[view] ?? false;
    final error = _errors[view];
    final items = _items[view];

    if (loading && (items == null || items.isEmpty)) return const LoadingView();

    if (error != null && (items == null || items.isEmpty)) {
      return PageErrorWidget(
        message: error,
        showBack: false,
        onRetry: () => _fetch(view, force: true),
      );
    }

    if (items == null || items.isEmpty) {
      return const EmptyView(icon: Icons.emoji_events_outlined, text: '暂无数据');
    }

    return RefreshIndicator(
      onRefresh: () => _fetch(view, force: true),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        itemCount: items.length,
        itemBuilder: (_, i) => _MemberRankTile(item: items[i]),
      ),
    );
  }
}

/// 用户排行条目：排名徽章 + 头像 + 昵称（+ 在线点 / 用户组）+ 统计行
class _MemberRankTile extends StatelessWidget {
  const _MemberRankTile({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rank = item['rank'] as int? ?? 0;
    final uid = item['uid']?.toString() ?? '';
    final username = item['username']?.toString() ?? '';
    final userGroup = item['userGroup']?.toString() ?? '';
    final userGroupColor = _parseColor(item['userGroupColor']?.toString());
    final online = item['online'] == true;
    final statLine = item['statLine']?.toString() ?? '';
    final isTop = rank > 0 && rank <= 3;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: uid.isEmpty ? null : () => context.push('/user/$uid'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              // 排名 —— 前三名实心徽章，其余只是数字
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isTop ? cs.primary : null,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$rank',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isTop ? cs.onPrimary : cs.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              UserAvatar(
                uid: uid,
                nickname: username,
                radius: 18,
                tapAction: AvatarTapAction.none,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (online) ...[
                          const SizedBox(width: 5),
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: Color(0xFF4CAF50),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                        if (userGroup.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: (userGroupColor ?? cs.primary).withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              userGroup,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: userGroupColor ?? cs.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (statLine.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        statLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
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

  /// 解析站点下发的 `#RRGGBB` 用户组颜色（空/非法返回 null）
  static Color? _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final v = hex.replaceFirst('#', '');
    if (v.length != 6) return null;
    final n = int.tryParse(v, radix: 16);
    return n == null ? null : Color(0xFF000000 | n);
  }
}
