import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/config/brand_colors.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/utils/cache_utils.dart';
import 'package:mtbbs/core/utils/string_utils.dart';
import 'package:mtbbs/api/home/space/export.dart' as space_api;
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/models/user_profile.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/models/browse_record.dart';
import 'package:mtbbs/providers/history_provider.dart';
import 'package:mtbbs/widgets/common/user_avatar.dart';
import 'package:mtbbs/widgets/common/pie_chart.dart';
import 'package:mtbbs/widgets/common/page_actions.dart';
import 'package:mtbbs/widgets/bbcode/post_html_widget.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';
import 'package:mtbbs/widgets/layout/page_error_widget.dart';
import 'package:mtbbs/widgets/layout/state_views.dart';
import 'package:mtbbs/pages/user/user_uid_picker_dialog.dart';

part 'user_profile_sections.dart';
part 'user_profile_sections_extra.dart';
part 'user_profile_credit_dialog.dart';

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
  bool _showRawSignature = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 供 part 扩展使用（扩展无法直接访问受保护的 setState）
  void _setState(VoidCallback fn) {
    if (mounted) setState(fn);
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
            id: '${SiteStore.instance.host}:user_${widget.uid}',
            host: SiteStore.instance.host,
            type: 'user',
            routePath: '/user/${widget.uid}',
            timestamp: DateTime.now(),
            info: {
              'uid': widget.uid,
              'nickname': profile.nickname,
              'avatar': profile.avatar,
              'url':
                  '${SiteStore.instance.baseUrl}/home.php?mod=space&uid=${widget.uid}&do=profile&from=space',
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

  int? get _uidNum => int.tryParse(widget.uid);

  void _navigateToUid(int uid) => GoRouter.of(context).replace('/user/$uid');

  void _showUidPicker() {
    showDialog(
      context: context,
      builder: (_) => UidPickerDialog(onNavigateToUid: _navigateToUid),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = _cs;
    final uidNum = _uidNum;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: GestureDetector(
          onTap: _showUidPicker,
          child: Text(
            _profile != null
                ? '${_profile!['nickname'] ?? '用户'}的主页 (${widget.uid})'
                : '用户主页 (${widget.uid})',
          ),
        ),
        surfaceTintColor: _cs.surface,
        elevation: 0.5,
        actions: [
          // TA 的关注 / 好友入口（仅数值 uid 显示；self 页入口在"我的"页）
          if (_uidNum != null) ...[
            IconButton(
              icon: const Icon(Icons.visibility_outlined),
              tooltip: 'TA的关注',
              onPressed: () =>
                  context.push('/follow?type=following&uid=${widget.uid}'),
            ),
            IconButton(
              icon: const Icon(Icons.people_outline),
              tooltip: 'TA的粉丝',
              onPressed: () =>
                  context.push('/follow?type=follower&uid=${widget.uid}'),
            ),
          ],
          PageActions(
            url:
                '${SiteStore.instance.baseUrl}/home.php?mod=space&uid=${widget.uid}&do=profile&from=space',
            onRefresh: _load,
            loading: _loading,
            copyLabel: '复制个人主页链接',
            extraItems: [
              if (uidNum != null) ...[
                PopupMenuItem<String>(
                  value: 'prev_user',
                  enabled: uidNum > 1,
                  child: Row(
                    children: [
                      Icon(
                        Icons.chevron_left,
                        size: 18,
                        color: uidNum > 1
                            ? null
                            : Theme.of(context).disabledColor,
                      ),
                      const SizedBox(width: 8),
                      const Text('上一个用户'),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'next_user',
                  child: Row(
                    children: [
                      const Icon(Icons.chevron_right, size: 18),
                      const SizedBox(width: 8),
                      const Text('下一个用户'),
                    ],
                  ),
                ),
              ],
            ],
            onExtraSelected: (action) {
              switch (action) {
                case 'prev_user':
                  if (uidNum != null && uidNum > 1) {
                    _navigateToUid(uidNum - 1);
                  }
                case 'next_user':
                  if (uidNum != null) {
                    _navigateToUid(uidNum + 1);
                  }
                case 'credit_analysis':
                  _showCreditDialog();
              }
            },
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return PageErrorWidget(message: _error!, onRetry: _load, showBack: false);
    }
    if (_profile == null) {
      return const EmptyView(icon: Icons.person_off_outlined, text: '无数据');
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          _buildHeader(),
          const SizedBox(height: 8),
          _buildPointsSection(),
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
