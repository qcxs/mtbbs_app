import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/api/home/pm/export.dart' as pm_api;
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/widgets/bbcode/post_html_widget.dart';
import 'package:mtbbs/widgets/common/page_actions.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';
import 'package:mtbbs/widgets/common/user_avatar.dart';
import 'package:mtbbs/widgets/layout/page_error_widget.dart';
import 'package:mtbbs/widgets/layout/state_views.dart';

/// 私信聊天页 —— 与单个用户的会话（气泡式）
///
/// 数据来自 `lib/api/home/pm/`：首屏拉**最新一页**，向上滚动按
/// `olderPage` 逐页追加更旧消息（Discuz 的 page 从最旧页 1 递增到最新）。
/// 正文是服务端渲染过的 HTML，经 `Html2BBCode` 还原后用 [PostHtmlWidget]
/// 渲染，与帖子正文同一套链路。
///
/// **实时轮询**：Discuz 没有"增量拉新消息"接口，只能按 [_kPollInterval]
/// 周期重拉最新一页、按 pmid 去重后追加。仅在页面挂载且应用处于前台时轮询，
/// 切后台/离开页面即停，避免无谓请求。
class PmChatPage extends StatefulWidget {
  /// 对方 uid
  final String touid;

  /// 对方用户名（列表/主页跳转时已知，用于首屏标题，可空）
  final String? username;

  const PmChatPage({super.key, required this.touid, this.username});

  @override
  State<PmChatPage> createState() => _PmChatPageState();
}

/// 轮询间隔。Discuz 无增量接口，只能整页重拉；5s 兼顾及时性与请求量。
const Duration _kPollInterval = Duration(seconds: 5);

/// 判定"用户是否已在底部"的像素阈值：超出则不因新消息自动滚屏（避免打断看历史）
const double _kNearBottomThreshold = 80;

class _PmChatPageState extends State<PmChatPage> with WidgetsBindingObserver {
  final _items = <Map<String, dynamic>>[];
  final _inputCtl = TextEditingController();
  final _scrollCtl = ScrollController();

  String _username = '';
  String _formhash = '';
  int _olderPage = 0;
  bool _hasOlder = false;
  bool _loading = true;
  bool _loadingOlder = false;
  bool _sending = false;
  String? _error;

  Timer? _pollTimer;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _username = widget.username ?? '';
    _loadNewest();
    _startPolling();
  }

  @override
  void dispose() {
    _stopPolling();
    WidgetsBinding.instance.removeObserver(this);
    _inputCtl.dispose();
    _scrollCtl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 前台才轮询：后台/未激活时停掉，恢复时立刻补一次
    if (state == AppLifecycleState.resumed) {
      _startPolling();
      _poll();
    } else {
      _stopPolling();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_kPollInterval, (_) => _poll());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// 轮询最新一页：把新增的消息追加到列表尾部
  ///
  /// 与首屏/发送复用同一接口，靠 pmid 去重；拉到新消息时，只有用户本来就在
  /// 底部才自动滚屏（否则正在看历史时会被打断）。
  Future<void> _poll() async {
    if (_polling || _loading || _loadingOlder || _sending || !mounted) return;
    // 页面被其他路由盖住（如从聊天页进了用户主页）时不轮询，回来再继续
    if (ModalRoute.of(context)?.isCurrent != true) return;
    _polling = true;
    final wasNearBottom = _isNearBottom();
    try {
      final result = await pm_api.getPmView(
        ApiService().dio,
        touid: widget.touid,
      );
      if (!mounted || result['success'] != true) return;
      final latest = _asItems(result['items']);
      final existing = _items.map((e) => e['pmid']).toSet();
      final fresh = latest.where((e) => !existing.contains(e['pmid'])).toList();
      if (fresh.isEmpty) {
        // 无新消息：只同步 formhash（会话过期时轮询顺便刷新），不触发重建
        final hash = result['formhash'] as String? ?? '';
        if (hash.isNotEmpty) _formhash = hash;
        return;
      }
      // 最新页与已加载区间完全不相交（离开太久、新消息多于一页）→ 整体重载，
      // 宁可重置视图也不要静默漏掉中间的消息
      if (existing.isNotEmpty && !existing.contains(latest.first['pmid'])) {
        AppLogger.d('PAGE', 'PmChatPage 轮询与已加载区间不相交，整体重载');
        await _loadNewest();
        return;
      }
      setState(() {
        _items.addAll(fresh);
        if ((result['formhash'] as String? ?? '').isNotEmpty) {
          _formhash = result['formhash'] as String;
        }
      });
      AppLogger.d('PAGE', 'PmChatPage 轮询到 ${fresh.length} 条新消息');
      if (wasNearBottom) _scrollToBottom();
    } catch (e) {
      // 轮询失败不打扰用户，静默留痕，下个周期重试
      AppLogger.w('PAGE', 'PmChatPage poll error: $e');
    } finally {
      _polling = false;
    }
  }

  bool _isNearBottom() {
    if (!_scrollCtl.hasClients) return true;
    final pos = _scrollCtl.position;
    return pos.maxScrollExtent - pos.pixels <= _kNearBottomThreshold;
  }

  /// 会话在站内的完整地址，供「在浏览器中打开 / 复制链接」使用
  String get _pageUrl =>
      '${SiteStore.instance.baseUrl}/home.php?mod=space&do=pm&subop=view&touid=${widget.touid}';

  /// 拉取最新一页并替换列表
  Future<void> _loadNewest() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await pm_api.getPmView(
        ApiService().dio,
        touid: widget.touid,
      );
      if (!mounted) return;
      if (result['success'] != true) {
        setState(() {
          _error = result['message'] as String? ?? '加载失败';
          _loading = false;
        });
        return;
      }
      setState(() {
        _items
          ..clear()
          ..addAll(_asItems(result['items']));
        _username = (result['username'] as String? ?? '').isNotEmpty
            ? result['username'] as String
            : _username;
        _formhash = result['formhash'] as String? ?? '';
        _olderPage = (result['olderPage'] as num?)?.toInt() ?? 0;
        _hasOlder = result['hasOlder'] == true;
        _loading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      AppLogger.w('PAGE', 'PmChatPage load error: $e');
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 向上加载更旧的一页，并保持当前阅读位置
  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasOlder || _olderPage <= 0) return;
    setState(() => _loadingOlder = true);

    final oldMax = _scrollCtl.hasClients
        ? _scrollCtl.position.maxScrollExtent
        : 0.0;
    try {
      final result = await pm_api.getPmView(
        ApiService().dio,
        touid: widget.touid,
        page: _olderPage,
      );
      if (!mounted) return;
      if (result['success'] != true) {
        showToast(result['message'] as String? ?? '加载更早消息失败');
        setState(() => _loadingOlder = false);
        return;
      }
      final older = _asItems(result['items']);
      final existing = _items.map((e) => e['pmid']).toSet();
      final fresh = older.where((e) => !existing.contains(e['pmid'])).toList();

      setState(() {
        _items.insertAll(0, fresh);
        _olderPage = (result['olderPage'] as num?)?.toInt() ?? 0;
        _hasOlder = result['hasOlder'] == true;
        if ((result['formhash'] as String? ?? '').isNotEmpty) {
          _formhash = result['formhash'] as String;
        }
        _loadingOlder = false;
      });
      // 前插内容会把可视区往上顶，按高度差补偿滚动位置
      _preserveScroll(oldMax);
    } catch (e) {
      if (!mounted) return;
      AppLogger.w('PAGE', 'PmChatPage loadOlder error: $e');
      showToast('加载更早消息失败');
      setState(() => _loadingOlder = false);
    }
  }

  Future<void> _send() async {
    final text = _inputCtl.text.trim();
    if (text.isEmpty || _sending) return;
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);
    try {
      final r = await pm_api.sendPm(
        ApiService().dio,
        touid: widget.touid,
        message: text,
        formhash: _formhash,
      );
      if (!mounted) return;
      if (!r.success) {
        showToast(r.message.isNotEmpty ? r.message : '发送失败');
        setState(() => _sending = false);
        return;
      }
      _inputCtl.clear();
      setState(() => _sending = false);
      // 重新拉最新页：保证 pmid/时间/正文与服务端一致
      await _loadNewest();
    } catch (e) {
      if (!mounted) return;
      AppLogger.w('PAGE', 'PmChatPage send error: $e');
      showToast('发送失败');
      setState(() => _sending = false);
    }
  }

  List<Map<String, dynamic>> _asItems(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtl.hasClients) return;
      _scrollCtl.jumpTo(_scrollCtl.position.maxScrollExtent);
    });
  }

  void _preserveScroll(double oldMax) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtl.hasClients) return;
      final delta = _scrollCtl.position.maxScrollExtent - oldMax;
      if (delta != 0) _scrollCtl.jumpTo(_scrollCtl.position.pixels + delta);
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = _username.isNotEmpty ? _username : '与用户 ${widget.touid}';
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => context.push('/user/${widget.touid}'),
          child: Text(title, overflow: TextOverflow.ellipsis),
        ),
        actions: [
          PageActions(
            url: _pageUrl,
            onRefresh: _loadNewest,
            loading: _loading,
            copyLabel: '复制会话链接',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty) return const LoadingView();
    if (_error != null && _items.isEmpty) {
      return PageErrorWidget(message: _error!, onRetry: _loadNewest);
    }
    if (_items.isEmpty) {
      return const EmptyView(
        icon: Icons.chat_bubble_outline,
        text: '还没有消息，发送第一条吧',
      );
    }

    return ListView.builder(
      controller: _scrollCtl,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      itemCount: _items.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return _buildOlderHeader();
        return _MessageBubble(
          item: _items[index - 1],
          onAvatarTap: () => context.push('/user/${widget.touid}'),
        );
      },
    );
  }

  Widget _buildOlderHeader() {
    if (_loadingOlder) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (!_hasOlder) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Text(
            '没有更早的消息了',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: TextButton(onPressed: _loadOlder, child: const Text('加载更早的消息')),
      ),
    );
  }

  Widget _buildInputBar() {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _inputCtl,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: '发送消息（支持 BBCode）',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            _sending
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.send),
                    color: cs.primary,
                    tooltip: '发送',
                    onPressed: _send,
                  ),
          ],
        ),
      ),
    );
  }
}

/// 单条消息气泡：自己发的靠右，对方的靠左并带头像
class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onAvatarTap;

  const _MessageBubble({required this.item, required this.onAvatarTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMine = item['isMine'] == true;
    final bbcode = item['bbcode'] as String? ?? '';
    final time = item['time'] as String? ?? '';
    final senderUid = item['senderUid'] as String? ?? '';
    final senderName = item['senderName'] as String? ?? '';

    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isMine ? cs.primaryContainer : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: PostHtmlWidget(bbcode: bbcode, fontSize: 14),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMine) ...[
            if (senderUid.isNotEmpty)
              UserAvatar(
                uid: senderUid,
                nickname: senderName,
                radius: 16,
                tapAction: AvatarTapAction.none,
              )
            else
              const SizedBox(width: 40),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * 0.78,
                  ),
                  child: Column(
                    crossAxisAlignment: isMine
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      bubble,
                      const SizedBox(height: 2),
                      Text(
                        time,
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
