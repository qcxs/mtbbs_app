import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/site_store.dart';
import '../../api/home/space/export.dart' as space_api;
import '../../services/api_service.dart';
import '../../models/user_profile.dart';
import '../../providers/settings_provider.dart';
import '../../models/browse_record.dart';
import '../../providers/history_provider.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/pie_chart.dart';
import '../../widgets/page_actions.dart';

/// 用户主页
///
/// 路径: /user/:uid
class UserProfilePage extends StatefulWidget {
  final String uid;
  const UserProfilePage({super.key, required this.uid});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  ColorScheme get _cs => Theme.of(context).colorScheme;
  Map<String, dynamic>? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await space_api.getUserProfile(
        ApiService().dio,
        uid: widget.uid == 'self' ? '' : widget.uid,
      );
      final profile = raw['success'] == true && raw['profile'] != null
          ? UserProfile.fromMap(raw['profile'] as Map<String, dynamic>)
          : null;
      if (profile == null) {
        setState(() {
          _error = '加载失败';
          _loading = false;
        });
        return;
      }
      setState(() {
        _profile = profile.toMap();
        _loading = false;
      });
      // 加载成功保存浏览记录
      if (context.mounted) {
        context.read<HistoryProvider>().addRecord(
          BrowseRecord(
            id: 'user_${widget.uid}',
            type: 'user',
            title: profile.nickname.isNotEmpty
                ? profile.nickname
                : '用户${widget.uid}',
            routePath: '/user/${widget.uid}',
            timestamp: DateTime.now(),
            info: {
              'uid': widget.uid,
              'nickname': profile.nickname,
              'avatar': profile.avatar,
              'url':
                  '${SiteStore.instance.baseUrl}/home.php?mod=space&uid=${widget.uid}',
            },
          ),
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = _cs;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: Text(
          _profile != null ? '${_profile!['nickname'] ?? '用户'}的主页' : '用户主页',
        ),
        surfaceTintColor: _cs.surface,
        elevation: 0.5,
        actions: [
          if (_profile != null)
            IconButton(
              icon: const Icon(Icons.pie_chart_outline, size: 20),
              tooltip: '积分分析',
              onPressed: _showCreditDialog,
            ),
          PageActions(
            url:
                '${SiteStore.instance.baseUrl}/home.php?mod=space&uid=${widget.uid}',
            onRefresh: _load,
            loading: _loading,
            copyLabel: '复制个人主页链接',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_off_outlined,
                size: 48,
                color: _cs.onSurfaceVariant,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: _cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_profile == null) {
      return const Center(child: Text('无数据'));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          _buildHeader(),
          const SizedBox(height: 8),
          _buildStatsCard(),
          const SizedBox(height: 8),
          _buildActivityStats(),
          const SizedBox(height: 8),
          if (_profile!['signature'] != null) _buildSignature(),
          if (_profile!['customTitle'] != null) ...[
            const SizedBox(height: 8),
            _buildCustomTitle(),
          ],
          const SizedBox(height: 8),
          _buildActivityInfo(),
          if (_profile!['medals'] != null) ...[
            const SizedBox(height: 8),
            _buildMedals(),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ==================== 用户头部 ====================

  Widget _buildHeader() {
    final p = _profile!;
    final nickname = p['nickname'] as String? ?? '未知';
    final uid = p['uid'] as String? ?? '';
    final online = p['online'] as bool? ?? false;
    final userGroup = _getNested(p, ['activity', 'userGroup']) as String?;
    final adminGroup = _getNested(p, ['activity', 'adminGroup']) as String?;
    final group = adminGroup ?? userGroup;

    return Container(
      padding: const EdgeInsets.all(20),
      color: _cs.surface,
      child: Row(
        children: [
          UserAvatar(
            uid: uid,
            nickname: nickname,
            radius: 32,
            tapAction: AvatarTapAction.viewAvatar,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      nickname,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (online)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '在线',
                          style: TextStyle(
                            fontSize: 11,
                            color: const Color(0xFF4CAF50),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'UID: $uid',
                  style: TextStyle(fontSize: 13, color: _cs.onSurfaceVariant),
                ),
                if (group != null && group.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9900).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      group,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFFF9900),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 积分卡片 ====================

  Widget _buildStatsCard() {
    final points = _profile!['points'] as Map<String, dynamic>?;
    if (points == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      color: _cs.surface,
      child: Row(
        children: [
          _statBox(
            '积分',
            points['credits']?.toString() ?? '0',
            Icons.monetization_on_outlined,
            const Color(0xFFFF9800),
          ),
          _divider(),
          _statBox(
            '好评',
            points['reputation']?.toString() ?? '0',
            Icons.thumb_up_outlined,
            const Color(0xFF4CAF50),
          ),
          _divider(),
          _statBox(
            '金币',
            points['goldCoins']?.toString() ?? '0',
            Icons.workspace_premium_outlined,
            const Color(0xFFFFC107),
          ),
          _divider(),
          _statBox(
            '信誉',
            points['credit']?.toString() ?? '0',
            Icons.verified_outlined,
            const Color(0xFF2196F3),
          ),
        ],
      ),
    );
  }

  Widget _statBox(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: _cs.onSurfaceVariant),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(width: 1, height: 36, color: _cs.outlineVariant);
  }

  // ==================== 活跃统计 ====================

  Widget _buildActivityStats() {
    final stats = _profile!['stats'] as Map<String, dynamic>?;
    if (stats == null) return const SizedBox.shrink();

    final uid = widget.uid;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      color: _cs.surface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _activityStatItem(
            Icons.people_outline,
            '好友',
            stats['friends']?.toString() ?? '0',
            const Color(0xFFE91E63),
          ),
          _activityStatItem(
            Icons.reply_outlined,
            '回帖',
            stats['replies']?.toString() ?? '0',
            const Color(0xFF00BCD4),
            onTap: () => context.push('/my-threads?type=reply&uid=$uid'),
          ),
          _activityStatItem(
            Icons.article_outlined,
            '主题',
            stats['threads']?.toString() ?? '0',
            const Color(0xFF9C27B0),
            onTap: () => context.push('/my-threads?uid=$uid'),
          ),
          _activityStatItem(
            Icons.share_outlined,
            '分享',
            stats['shares']?.toString() ?? '0',
            const Color(0xFFFF5722),
          ),
        ],
      ),
    );
  }

  Widget _activityStatItem(
    IconData icon,
    String label,
    String value,
    Color color, {
    VoidCallback? onTap,
  }) {
    final content = Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: _cs.onSurfaceVariant),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: content,
        ),
      );
    }
    return content;
  }

  // ==================== 积分分析弹窗 ====================

  /// 显示积分分析弹窗（饼图 + 积分占比 + 精华帖数）
  void _showCreditDialog() {
    final settings = context.read<SettingsProvider>();
    if (settings.creditFormula.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请登录后在设置页面中刷新积分公式后使用')));
      return;
    }

    final p = _profile!;
    final computed = _computeCreditData(p);
    if (computed == null) return;

    final segments = computed.$1;
    final totalCalc = computed.$2;
    final elitePosts = computed.$3;
    final formulaStr = computed.$4;
    final diff = computed.$5;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.pie_chart_outline,
                      size: 18,
                      color: _cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      '积分分析',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '公式: $formulaStr',
                  style: TextStyle(
                    fontSize: 10,
                    color: _cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (diff < 10) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        '估算精华帖: ',
                        style: TextStyle(
                          fontSize: 14,
                          color: _cs.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '$elitePosts 篇',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '(可能不准确)',
                        style: TextStyle(
                          fontSize: 12,
                          color: _cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                // 饼图 + 图例
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    PieChart(segments: segments, size: 130, strokeWidth: 30),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: segments.map((s) {
                          final pct = (s.value / totalCalc * 100);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: s.color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    s.label,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${pct.toStringAsFixed(1)}%',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 计算积分分析数据，返回 (segments, totalCalc, elitePosts, formulaStr, diff)
  (List<PieChartSegment>, double, int, String, double)? _computeCreditData(
    Map<String, dynamic> p,
  ) {
    final points = p['points'] as Map<String, dynamic>? ?? {};
    final stats = p['stats'] as Map<String, dynamic>? ?? {};
    final activity = p['activity'] as Map<String, dynamic>? ?? {};

    final credits = _n(points['credits']);
    final goldCoins = _n(points['goldCoins']);
    final threads = _n(stats['threads']);
    final replies = _n(stats['replies']);
    final totalPosts = threads + replies;
    final reputation = _n(points['reputation']);
    final credit = _n(points['credit']);
    final friends = _n(stats['friends']);
    final onlineTime = _extractHours(activity['onlineTime'] as String?);

    if (credits <= 0) return null;

    final settings = context.read<SettingsProvider>();
    final formulaStr = settings.creditFormula;

    final termGold = goldCoins * 0.2;
    final termThreads = threads * 3;
    final termPosts = totalPosts * 1.5;
    final termReputation = reputation * 5;
    final termCredit = (credit - 100) * 5;
    final termFriends = (1 - 1 / (friends / 500 + 1)) * 5000;
    final termOnline = (1 - 1 / (onlineTime / 5000 + 1)) * 20000;

    final knownSum =
        termGold +
        termThreads +
        termPosts +
        termReputation +
        termCredit +
        termFriends +
        termOnline;

    final eliteContribution = credits - knownSum;
    final elitePosts = (eliteContribution / 30).round().clamp(0, 999);
    final termElite = elitePosts * 30.0;

    final totalCalc = knownSum + termElite;
    final diff = (totalCalc - credits).abs();

    final segments = <PieChartSegment>[];
    void addSeg(String label, double value, Color color) {
      if (value > 0.5) {
        segments.add(PieChartSegment(label: label, value: value, color: color));
      }
    }

    addSeg('金币', termGold, const Color(0xFFFFC107));
    addSeg('主题', termThreads, const Color(0xFF3F51B5));
    addSeg('发帖', termPosts, const Color(0xFF00BCD4));
    if (elitePosts > 0) addSeg('精华', termElite, const Color(0xFFFF9800));
    addSeg('好评', termReputation, const Color(0xFF4CAF50));
    addSeg('信誉', termCredit < 0 ? 0 : termCredit, const Color(0xFF2196F3));
    addSeg('好友', termFriends, const Color(0xFFE91E63));
    addSeg('在线', termOnline, const Color(0xFF9C27B0));

    return (segments, totalCalc, elitePosts, formulaStr, diff);
  }

  /// 从 "5754 小时" 中提取数字
  double _extractHours(String? str) {
    if (str == null || str.isEmpty) return 0;
    final match = RegExp(r'([\d,.]+)').firstMatch(str);
    if (match == null) return 0;
    return _n(match.group(1));
  }

  double _n(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '').trim()) ?? 0;
  }

  // ==================== 个性签名 ====================

  Widget _buildSignature() {
    final sig = _profile!['signature'] as String? ?? '';
    if (sig.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      color: _cs.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.format_quote, size: 16, color: _cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                '个性签名',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            sig.replaceAll(RegExp(r'\[/?\w+(=[^\]]*)?\]'), ''),
            style: TextStyle(
              fontSize: 14,
              color: _cs.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 自定义头衔 ====================

  Widget _buildCustomTitle() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: _cs.surface,
      child: Row(
        children: [
          Icon(Icons.badge_outlined, size: 16, color: _cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            '头衔: ',
            style: TextStyle(fontSize: 13, color: _cs.onSurfaceVariant),
          ),
          Text(
            _profile!['customTitle'] as String? ?? '',
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ==================== 活跃概况 ====================

  Widget _buildActivityInfo() {
    final activity = _profile!['activity'] as Map<String, dynamic>?;
    if (activity == null) return const SizedBox.shrink();

    final items = <MapEntry<String, String>>[];
    void add(String label, String? value) {
      if (value != null && value.isNotEmpty) {
        items.add(MapEntry(label, value));
      }
    }

    add('在线时间', activity['onlineTime'] as String?);
    add('注册时间', activity['registerTime'] as String?);
    add('最后访问', activity['lastVisit'] as String?);
    add('上次活动', activity['lastActivityTime'] as String?);
    add('上次发表', activity['lastPostTime'] as String?);

    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: _cs.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bar_chart_outlined,
                size: 16,
                color: _cs.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                '活跃概况',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      item.key,
                      style: TextStyle(
                        fontSize: 13,
                        color: _cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(item.value, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 勋章 ====================

  Widget _buildMedals() {
    final medals = _profile!['medals'] as List<dynamic>? ?? [];
    if (medals.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      color: _cs.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.emoji_events_outlined,
                size: 16,
                color: _cs.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                '勋章 (${medals.length})',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: medals.map((m) {
              final medal = m as Map<String, dynamic>;
              final name = medal['name'] as String? ?? '';
              final icon = medal['icon'] as String? ?? '';
              return Tooltip(
                message: name,
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: icon.isNotEmpty
                      ? CachedNetworkImage(imageUrl: icon, fit: BoxFit.contain)
                      : Container(
                          decoration: BoxDecoration(
                            color: _cs.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Icon(
                            Icons.emoji_events_outlined,
                            size: 18,
                            color: _cs.onSurfaceVariant,
                          ),
                        ),
                ),
              );
            }).toList(),
          ),
          if (medals.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: medals.map((m) {
                final medal = m as Map<String, dynamic>;
                final name = medal['name'] as String? ?? '';
                return Text(
                  name,
                  style: TextStyle(fontSize: 11, color: _cs.onSurfaceVariant),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  /// 从嵌套 Map 中安全取值
  dynamic _getNested(Map<String, dynamic> map, List<String> keys) {
    dynamic value = map;
    for (final key in keys) {
      if (value is Map<String, dynamic>) {
        value = value[key];
      } else {
        return null;
      }
    }
    return value;
  }
}
