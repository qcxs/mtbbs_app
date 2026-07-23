import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/site_store.dart';
import '../../core/url_router.dart';
import '../../core/username_validator.dart';
import '../../providers/search_history_provider.dart';
import '../../api/home/space/export.dart' as space_api;
import '../../services/api_service.dart';
import '../../models/user_profile.dart';

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

  /// 输入是否匹配用户搜索条件：纯数字（uid）或合法用户名
  bool _hasUserMatch(String text) {
    if (text.isEmpty) return false;
    if (UsernameValidator.isNumeric(text)) return true;
    return UsernameValidator.validate(text).isValid;
  }

  /// 用户搜索建议的显示文字
  String _userSearchLabel(String text) {
    if (UsernameValidator.isNumeric(text)) {
      return '查看用户 (UID: $text)';
    }
    return '查看用户 "$text"';
  }

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('请切换站点${result.siteName ?? ""}后再打开'),
          duration: const Duration(seconds: 3),
        ),
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
    final url =
        'https://www.bing.com/search?q=${Uri.encodeComponent('$query site:$domain')}';
    context.push('/browser?url=${Uri.encodeComponent(url)}');
  }

  Future<void> _performSiteSearch(String query) async {
    await _addHistory(query);
    if (!mounted) return;
    final url =
        '${SiteStore.instance.baseUrl}/search.php?mod=forum&srchtxt=${Uri.encodeComponent(query)}&searchsubmit=yes';
    context.push('/browser?url=${Uri.encodeComponent(url)}');
  }

  Future<void> _addHistory(String text) async {
    if (text.isEmpty) return;
    try {
      await context.read<SearchHistoryProvider>().add(text);
    } catch (_) {}
  }

  /// 通过 uid 或用户名查找用户并跳转
  Future<void> _lookupUser(String input) async {
    await _addHistory(input);
    if (!mounted) return;

    final isNum = UsernameValidator.isNumeric(input);
    String? uid;

    if (isNum) {
      uid = input; // 纯数字直接当 uid 用
    } else {
      // 按用户名查询，获取 uid
      try {
        final raw = await space_api.getUserProfile(
          ApiService().dio,
          username: input,
        );
        final profile = raw['success'] == true && raw['profile'] != null
            ? UserProfile.fromMap(raw['profile'] as Map<String, dynamic>)
            : null;
        uid = profile?.uid;
      } catch (_) {
        uid = null;
      }
    }

    if (!mounted) return;

    if (uid == null || uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未找到该用户'), duration: Duration(seconds: 2)),
      );
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
        if (_hasUserMatch(text)) ...[
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
          backgroundColor: iconColor.withOpacity(0.1),
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
