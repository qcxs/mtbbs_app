import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/utils/url_router.dart';
import 'package:mtbbs/core/utils/username_validator.dart';
import 'package:mtbbs/providers/search_history_provider.dart';
import 'package:mtbbs/api/home/space/export.dart' as space_api;
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/models/user_profile.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';

/// 搜索页面
///
/// 独立路由页面，避免 AlertDialog 的布局限制。
/// 独立使用 SearchHistoryProvider 存储搜索历史，不与浏览历史混淆。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  UrlRouteResult? _routeResult;
  bool _isUrl = false;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _controller.text.trim();
    setState(() {
      _isUrl = text.isNotEmpty && _isLikelyUrl(text);
      _routeResult = _isUrl ? UrlRouter.parse(text) : null;
    });
  }

  bool _isLikelyUrl(String text) {
    return text.contains('://') ||
        (text.contains('.') && !text.contains(' ')) ||
        text.contains('forum.php') ||
        text.contains('thread-') ||
        text.contains('home.php') ||
        text.contains('space-uid');
  }

  /// 输入是否可能是某个用户（UID 或用户名）—— 搜索建议用的**宽松判定**。
  ///
  /// 刻意不套用 [UsernameValidator]：那是**注册**规则（3~15 字符、仅汉字/字母/数字/
  /// 下划线），而论坛里真实存在的用户名可能更短、更长，或是一串数字（如手机号）；
  /// 按注册规则过滤会让这些用户"搜不到"。这里只排除明显不像用户名的输入：
  /// 带空白（Discuz 用户名不允许空格）或过长（多半是一句话 / 关键词）。
  bool _hasUserMatch(String text) {
    if (text.isEmpty || text.length > 30) return false;
    return !text.contains(RegExp(r'\s'));
  }

  /// 用户搜索建议的显示文字（不区分 UID / 用户名——数字也可能是用户名）
  String _userSearchLabel(String text) => '查看用户 "$text"';

  // ==================== 动作 ====================

  Future<void> _openInApp(String input) async {
    await _addHistory(input);
    if (!mounted) return;

    final fullUrl = input.contains('://')
        ? input
        : '${SiteStore.instance.baseUrl}/$input';
    final result = UrlRouter.parse(fullUrl);

    if (result.isOtherSite) {
      if (!mounted) return;
      showToast(
        '请切换站点${result.siteName ?? ""}后再打开',
        duration: const Duration(seconds: 3),
      );
      return;
    }

    if (result.appPath != null && mounted) {
      context.push(result.appPath!);
    }
  }

  Future<void> _openInBrowser(String input) async {
    await _addHistory(input);
    if (!mounted) return;

    final fullUrl = input.contains('://')
        ? input
        : '${SiteStore.instance.baseUrl}/$input';
    context.push(
      '/browser?url=${Uri.encodeComponent(fullUrl)}&intercept=false',
    );
  }

  Future<void> _performBingSearch(String query) async {
    await _addHistory(query);
    if (!mounted) return;
    final domain = Uri.tryParse(SiteStore.instance.baseUrl)?.host ?? '';
    // `form=QBRE` 是 Bing 搜索框表单的固定参数，必须带上：Bing 据此判断"用户是从
    // 搜索框提交的"，才会正确解析 `site:` 限定。缺了它，直连 URL 会被 Bing 当作
    // 外部跳转改写查询（URL 追加 rdr=1），`site:` 被静默丢弃——品牌词（如「MT管理器」）
    // 必现，返回全网结果；这是"结果不准"的根因。
    final q = Uri.encodeComponent('$query site:$domain');
    final url = 'https://www.bing.com/search?q=$q&form=QBRE';
    context.push('/browser?url=${Uri.encodeComponent(url)}');
  }

  Future<void> _performSiteSearch(String query) async {
    final kw = query.trim();
    if (kw.isEmpty) return;
    await _addHistory(kw);
    if (!mounted) return;
    context.push('/search/result?kw=${Uri.encodeComponent(kw)}');
  }

  Future<void> _addHistory(String text) async {
    if (text.isEmpty) return;
    try {
      await context.read<SearchHistoryProvider>().add(text);
    } catch (_) {}
  }

  /// 按 uid 或用户名查一次用户，命中则返回其 uid
  Future<String?> _resolveUid({String? uid, String? username}) async {
    try {
      final raw = await space_api.getUserProfile(
        ApiService().dio,
        uid: uid ?? '',
        username: username ?? '',
      );
      if (raw['success'] != true || raw['profile'] == null) return null;
      final profile = UserProfile.fromMap(
        raw['profile'] as Map<String, dynamic>,
      );
      return profile.uid.isNotEmpty ? profile.uid : uid;
    } catch (_) {
      return null;
    }
  }

  /// 通过 UID 或用户名查找用户并跳转。
  ///
  /// 纯数字**不能直接当 UID**：论坛里「用户名就是一串数字（如手机号）」真实存在，
  /// 因此数字输入先按 UID 查、查不到再按用户名查一次，都失败才提示未找到。
  Future<void> _lookupUser(String input) async {
    await _addHistory(input);
    if (!mounted) return;

    final uid = UsernameValidator.isNumeric(input)
        ? (await _resolveUid(uid: input) ?? await _resolveUid(username: input))
        : await _resolveUid(username: input);

    if (!mounted) return;

    if (uid == null || uid.isEmpty) {
      showToast('未找到该用户');
      return;
    }

    context.push('/user/$uid');
  }

  void _fillFromHistory(String text) {
    _controller.text = text;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final searchHistory = context.watch<SearchHistoryProvider>();
    final allItems = searchHistory.getAll();
    final text = _controller.text.trim();

    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: cs.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '搜索或输入链接...',
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 8),
          ),
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          if (text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear, size: 20),
              onPressed: () => _controller.clear(),
            ),
        ],
      ),
      body: text.isNotEmpty ? _buildSuggestions(text) : _buildHistory(allItems),
    );
  }

  // ==================== 历史记录（点击填充搜索框） ====================

  Widget _buildHistory(List<SearchHistoryItem> items) {
    final cs = Theme.of(context).colorScheme;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 48, color: cs.surfaceContainerHigh),
            const SizedBox(height: 12),
            Text(
              '暂无搜索历史',
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: items.length + 1,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Text(
                  '搜索历史',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    context.read<SearchHistoryProvider>().clear();
                  },
                  child: Text(
                    '清空',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          );
        }
        final item = items[i - 1];
        return ListTile(
          dense: true,
          leading: Icon(Icons.history, size: 18, color: cs.onSurfaceVariant),
          title: Text(
            item.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14),
          ),
          subtitle: Text(
            '点击填充到搜索框',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          trailing: IconButton(
            icon: Icon(Icons.close, size: 16, color: cs.onSurfaceVariant),
            onPressed: () {
              context.read<SearchHistoryProvider>().remove(item.text);
            },
          ),
          onTap: () => _fillFromHistory(item.text),
        );
      },
    );
  }

  // ==================== 搜索建议 ====================

  Widget _buildSuggestions(String text) {
    final cs = Theme.of(context).colorScheme;
    final domain = Uri.tryParse(SiteStore.instance.baseUrl)?.host ?? '';

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      children: [
        if (_isUrl) ...[
          if (_routeResult?.appPath != null)
            _suggestionCard(
              icon: Icons.open_in_new,
              iconColor: cs.onSurfaceVariant,
              label: '打开页面：${_routeResult!.label}',
              subtitle: _routeResult!.siteName != null
                  ? '[${_routeResult!.siteName}] ${_routeResult!.appPath}'
                  : _routeResult!.appPath,
              onTap: () => _openInApp(text),
            ),
          _suggestionCard(
            icon: Icons.language,
            iconColor: const Color(0xFF607D8B),
            label: '在浏览器中打开',
            subtitle: text,
            onTap: () => _openInBrowser(text),
          ),
          const Divider(height: 16),
        ],
        // 链接输入交给上面的「打开页面 / 浏览器」建议，不再当作用户名
        if (_hasUserMatch(text) && !_isUrl) ...[
          _suggestionCard(
            icon: Icons.person,
            iconColor: cs.onSurfaceVariant,
            label: _userSearchLabel(text),
            subtitle: '查看用户主页',
            onTap: () => _lookupUser(text),
          ),
          const Divider(height: 16),
        ],
        Text(
          '搜索',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        _suggestionCard(
          icon: Icons.forum,
          iconColor: cs.onSurfaceVariant,
          label: '站内搜索"$text"',
          subtitle: '$domain · Discuz 搜索',
          onTap: () => _performSiteSearch(text),
        ),
        _suggestionCard(
          icon: Icons.search,
          iconColor: const Color(0xFF00BCD4),
          label: 'Bing 搜索"$text"',
          subtitle: '限定站点 $domain',
          onTap: () => _performBingSearch(text),
        ),
      ],
    );
  }

  Widget _suggestionCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: iconColor.withValues(alpha: 0.1),
          child: Icon(icon, size: 20, color: iconColor),
        ),
        title: Text(label, style: const TextStyle(fontSize: 14)),
        subtitle: subtitle != null
            ? Text(
                subtitle,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: onTap,
      ),
    );
  }
}
