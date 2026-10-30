import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/config/brand_colors.dart';
import 'package:mtbbs/core/app/app_capabilities.dart';
import 'package:mtbbs/core/app/site_session.dart';
import 'package:mtbbs/core/app/site_scope.dart';
import 'package:mtbbs/core/utils/cache_utils.dart';
import 'package:mtbbs/core/utils/string_utils.dart';
import 'package:mtbbs/api/home/space/export.dart' as space_api;
import 'package:mtbbs/auth/providers/auth_provider.dart';
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
import 'package:mtbbs/pages/user/user_share_page.dart';

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

  /// 当前页面作用域的站点会话（跨站点打开时 = 目标站默认账号/游客，只读）
  SiteSession _session = const GlobalSiteSession();
  Dio get _dio => _session.dio;
  bool _sessionBound = false;

  /// 「生成图片」预览模式：正文区切换为预览（复用本页区块，见 _contentSections）
  bool _sharing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session = SiteScope.of(context);
    if (_sessionBound) return;
    _sessionBound = true;
    _load();
  }

  /// 跨站点只读守卫：命中时提示并返回 true
  bool _guardReadOnly() {
    if (!_session.temporary) return false;
    showToast('跨站点浏览为只读：发帖/留言/私信请先切换到目标站点');
    return true;
  }

  /// 打开 App 内页面；跨站时目标页未迁移 → 提示先切站点
  void _openAppPath(String appPath) {
    if (_guardReadOnly()) return;
    context.push(appPath);
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
        _dio,
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
      // 加载成功保存浏览记录（跨站点临时浏览不计入当前站点历史）
      if (context.mounted && !_session.temporary) {
        context.read<HistoryProvider>().addRecord(
          BrowseRecord(
            id: '${_session.host}:user_${widget.uid}',
            host: _session.host,
            type: 'user',
            routePath: '/user/${widget.uid}',
            timestamp: DateTime.now(),
            info: {
              'uid': widget.uid,
              'nickname': profile.nickname,
              'avatar': profile.avatar,
              'url':
                  '${_session.baseUrl}/home.php?mod=space&uid=${widget.uid}&do=profile&from=space',
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

  void _navigateToUid(int uid) => GoRouter.of(
    context,
  ).replace(SiteScope.pathFor(context, '/user/$uid'));

  void _showUidPicker() {
    showDialog(
      context: context,
      builder: (_) => UidPickerDialog(onNavigateToUid: _navigateToUid),
    );
  }

  /// 生成个人主页分享图（见 pages/user/user_share_page.dart）
  ///
  /// 直接复用本页正文区块（`_contentSections`）→ 图片与页面完全一致，无需任何配置。
  void _shareImage() {
    if (_profile == null) return;
    setState(() => _sharing = true);
  }

  /// 正文区块（正文列表与「生成图片」共用，保证图片与页面完全一致）
  List<Widget> _contentSections() => [
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
  ];

  /// 数据源菜单行：图标 + 文案 + 勾选
  Widget _sourceMenuRow({
    required IconData icon,
    required String label,
    required bool selected,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Text(label),
        const Spacer(),
        if (selected) const Icon(Icons.check, size: 16),
      ],
    );
  }

  /// 设置本页数据源并重新加载（'' = 跟随浏览模式 / 'mobile' / 'desktop'）
  Future<void> _setSpaceSource(String value) async {
    await context.read<SettingsProvider>().setSpaceSource(value);
    if (mounted) await _load();
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
          PageActions(
            url:
                '${_session.baseUrl}/home.php?mod=space&uid=${widget.uid}&do=profile&from=space',
            onRefresh: _load,
            loading: _loading,
            copyLabel: '复制个人主页链接',
            extraItems: [
              // 生成分享图（与帖子/评论同一套：预览 → 截图保存）
              if (AppCapabilities.isAvailable(AppCapability.saveImage)) ...[
                PopupMenuItem<String>(
                  value: 'save_image',
                  child: Row(
                    children: [
                      const Icon(Icons.save_alt, size: 18),
                      const SizedBox(width: 8),
                      const Text('生成图片'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
              ],
              // 本页数据源（仅个人空间生效）：移动版社交数据全，桌面版资料更全
              PopupMenuItem<String>(
                value: 'src_follow',
                child: _sourceMenuRow(
                  icon: Icons.sync,
                  label: '跟随浏览模式',
                  selected: space_api.spaceSourceOverride.isEmpty,
                ),
              ),
              PopupMenuItem<String>(
                value: 'src_mobile',
                child: _sourceMenuRow(
                  icon: Icons.smartphone_outlined,
                  label: '移动版',
                  selected: space_api.spaceSourceOverride == 'mobile',
                ),
              ),
              PopupMenuItem<String>(
                value: 'src_desktop',
                child: _sourceMenuRow(
                  icon: Icons.desktop_windows_outlined,
                  label: '桌面版',
                  selected: space_api.spaceSourceOverride == 'desktop',
                ),
              ),
              if (uidNum != null) ...[
                const PopupMenuDivider(),
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
                case 'save_image':
                  _shareImage();
                case 'src_follow':
                  _setSpaceSource('');
                case 'src_mobile':
                  _setSpaceSource('mobile');
                case 'src_desktop':
                  _setSpaceSource('desktop');
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
      body: _sharing ? _buildSharePreview() : _buildBody(),
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
      child: ListView(children: _contentSections()),
    );
  }

  /// 生成图片预览：复用本页正文区块（与页面完全一致）+ 底部「站点 / 用户 / 二维码」水印
  Widget _buildSharePreview() {
    final p = _profile!;
    final nickname = p['nickname'] as String? ?? '';
    final spaceUrl = p['spaceUrl'] as String? ?? '';
    return UserSharePreview(
      sections: _contentSections(),
      userLabel: nickname.isEmpty
          ? 'uid=${widget.uid}'
          : '$nickname · uid=${widget.uid}',
      qrUrl: spaceUrl.isNotEmpty
          ? spaceUrl
          : '${_session.baseUrl}/home.php?mod=space&uid=${widget.uid}&do=profile&from=space',
      siteHost: _session.host,
      filePrefix: 'MTBBS_user_${widget.uid}',
      onClose: () => setState(() => _sharing = false),
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
