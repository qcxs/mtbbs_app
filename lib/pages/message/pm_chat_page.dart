import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/api/home/pm/export.dart' as pm_api;
import 'package:mtbbs/auth/providers/auth_provider.dart';
import 'package:mtbbs/core/app/emoji_loader.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/widgets/bbcode/post_html_widget.dart';
import 'package:mtbbs/widgets/common/page_actions.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';
import 'package:mtbbs/widgets/common/user_avatar.dart';
import 'package:mtbbs/widgets/dialog/confirm_dialog.dart';
import 'package:mtbbs/widgets/layout/page_error_widget.dart';
import 'package:mtbbs/widgets/layout/state_views.dart';

/// 私信聊天页 —— 与单个用户的会话（气泡式）
///
/// 数据来自 `lib/api/home/pm/`：首屏拉**最新一页**，向上滚动按
/// `olderPage` 逐页追加更旧消息（Discuz 的 page 从最旧页 1 递增到最新）。
/// 正文是服务端渲染过的 HTML，经 `Html2BBCode` 还原后用 [PostHtmlWidget]
/// 渲染，与帖子正文同一套链路。
///
/// **滚动锚点**：列表用 `reverse: true`，以底部（最新消息）为锚点。向上加载
/// 旧消息时内容追加在视觉顶部，不会顶动可视区；即使旧消息里的图片懒加载后
/// 才撑开高度，也不会引起错位（正向列表按"高度差补偿"做的话则会错位）。
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
/// （reverse 列表下底部即 offset 0，故直接比较 pixels）
const double _kNearBottomThreshold = 80;

class _PmChatPageState extends State<PmChatPage> with WidgetsBindingObserver {
  final _items = <Map<String, dynamic>>[];

  /// 本地乐观发送的消息（服务端尚未确认），渲染在列表末尾。
  /// 每条含 `_localId` / `_status`(sending|sent|failed) / `isMine` / `bbcode` / `time` / `_error`。
  final _pending = <Map<String, dynamic>>[];
  final _inputCtl = TextEditingController();
  final _scrollCtl = ScrollController();

  String _username = '';
  String _formhash = '';
  int _olderPage = 0;
  bool _hasOlder = false;
  bool _loading = true;
  bool _loadingOlder = false;
  String? _error;

  /// 是否有消息正在发送（轮询避让用）
  bool get _sending => _pending.any((m) => m['_status'] == 'sending');

  /// 是否有发送失败、尚未处理的消息。
  /// 失败消息只存在内存里（`_pending`），退出页面即丢失，因此返回时需二次确认。
  bool get _hasFailedMessage => _pending.any((m) => m['_status'] == 'failed');

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
    final oldMax = _scrollCtl.hasClients
        ? _scrollCtl.position.maxScrollExtent
        : 0.0;
    try {
      await EmojiService().load();
      final result = await pm_api.getPmView(
        ApiService().dio,
        touid: widget.touid,
      );
      if (!mounted || result['success'] != true) return;
      // 请求期间若开始了发送 / 重拉，本次轮询结果已过期：直接丢弃，
      // 否则会把服务端那条重复灌进列表（表现为"发送中突然多出一条"）
      if (_sending || _loading) return;
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
        // 新到的"自己发的"消息会把本地已发送占位交出去（重拉失败时的兜底收敛）
        _dropCoveredSentPending(fresh);
        if ((result['formhash'] as String? ?? '').isNotEmpty) {
          _formhash = result['formhash'] as String;
        }
      });
      AppLogger.d('PAGE', 'PmChatPage 轮询到 ${fresh.length} 条新消息');
      if (wasNearBottom) {
        _scrollToBottom();
      } else {
        // reverse 列表在底部插入新消息会顶动可视区，补偿滚动位置保持阅读点
        _preserveScroll(oldMax);
      }
    } catch (e) {
      // 轮询失败不打扰用户，静默留痕，下个周期重试
      AppLogger.w('PAGE', 'PmChatPage poll error: $e');
    } finally {
      _polling = false;
    }
  }

  bool _isNearBottom() {
    if (!_scrollCtl.hasClients) return true;
    // reverse 列表：offset 0 即最新消息（底部）
    return _scrollCtl.position.pixels <= _kNearBottomThreshold;
  }

  /// 会话在站内的完整地址，供「在浏览器中打开 / 复制链接」使用
  String get _pageUrl =>
      '${SiteStore.instance.baseUrl}/home.php?mod=space&do=pm&subop=view&touid=${widget.touid}';

  /// 拉取最新一页并替换列表
  ///
  /// 替换 `_items` 与"交出已发送的本地占位"在同一帧内完成（原子交接），避免
  /// "消息消失 / 重复"的一帧。**但只有当重拉确实带回了新消息（出现新 pmid）时
  /// 才交出占位**：Discuz 私信存在"读后写"延迟，发送成功后的首次重拉可能仍返回
  /// 旧页（实测 `totalCount` 已 +1，但条目还是上一页的），此时若照删占位，
  /// 消息就会消失到下一次轮询；保留占位，等轮询拿到真身再收敛。
  Future<void> _loadNewest() async {
    final prevPmids = _items.map((e) => e['pmid']).toSet();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await EmojiService().load();
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
      final items = _asItems(result['items']);
      final appeared = items
          .where((e) => !prevPmids.contains(e['pmid']))
          .toList();
      setState(() {
        _items
          ..clear()
          ..addAll(items);
        _username = (result['username'] as String? ?? '').isNotEmpty
            ? result['username'] as String
            : _username;
        _formhash = result['formhash'] as String? ?? '';
        _olderPage = (result['olderPage'] as num?)?.toInt() ?? 0;
        _hasOlder = result['hasOlder'] == true;
        _loading = false;
        _dropCoveredSentPending(appeared);
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

  /// 向上加载更旧的一页
  ///
  /// reverse 列表以底部为锚点，旧消息插到列表末尾（视觉顶部）不会顶动可视区，
  /// 因此无需按高度差补偿滚动位置——图片懒加载导致的高度变化也不会再引起错位。
  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasOlder || _olderPage <= 0) return;
    setState(() => _loadingOlder = true);

    try {
      await EmojiService().load();
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
    } catch (e) {
      if (!mounted) return;
      AppLogger.w('PAGE', 'PmChatPage loadOlder error: $e');
      showToast('加载更早消息失败');
      setState(() => _loadingOlder = false);
    }
  }

  Future<void> _send() async {
    final text = _inputCtl.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    // 乐观更新：先本地插入一条"发送中"气泡，再真正提交
    final localId = 'local_${DateTime.now().microsecondsSinceEpoch}';
    // 自己发的消息也带头像：占位期间先用自己的 uid 渲染（服务端消息同样给该字段）
    final myUid = context.read<AuthProvider>().uid;
    setState(() {
      _pending.add(<String, dynamic>{
        '_localId': localId,
        '_status': 'sending',
        'isMine': true,
        'senderUid': myUid,
        'bbcode': text,
        'time': '',
      });
      _inputCtl.clear();
    });
    _scrollToBottom();
    await _submitLocal(localId, text);
  }

  /// 提交一条本地消息：成功则重拉最新页使消息落地，失败保留气泡并标叹号
  Future<void> _submitLocal(String localId, String text) async {
    _markStatus(localId, 'sending');
    try {
      final r = await pm_api.sendPm(
        ApiService().dio,
        touid: widget.touid,
        message: text,
        formhash: _formhash,
      );
      if (!mounted) return;
      if (!r.success) {
        final msg = r.message.isNotEmpty ? r.message : '发送失败';
        _markStatus(localId, 'failed', error: msg);
        showToast(msg);
        return;
      }
      // 成功：先去掉"发送中"，再重拉。重拉若带回真身就在同一帧内交出占位，
      // 若服务端读后写延迟返回旧页，则占位继续显示为"已发送"，等轮询收敛。
      _markStatus(localId, 'sent');
      await _loadNewest();
    } catch (e) {
      if (!mounted) return;
      AppLogger.w('PAGE', 'PmChatPage send error: $e');
      _markStatus(localId, 'failed', error: '发送失败');
      showToast('发送失败');
    }
  }

  /// 点击失败气泡的叹号：弹出「重新发送 / 删除」操作。
  /// 失败内容只存在内存里，删除即从本地列表中移除（服务端本就没有它）。
  Future<void> _showFailedActions(Map<String, dynamic> item) async {
    final localId = item['_localId'] as String? ?? '';
    if (localId.isEmpty) return;
    final error = item['_error'] as String? ?? '发送失败';
    final cs = Theme.of(context).colorScheme;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                error,
                style: TextStyle(fontSize: 13, color: cs.error),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('重新发送'),
              onTap: () => Navigator.of(ctx).pop('retry'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: cs.error),
              title: Text('删除', style: TextStyle(color: cs.error)),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'retry') {
      _submitLocal(localId, item['bbcode'] as String? ?? '');
    } else if (action == 'delete') {
      setState(() => _pending.removeWhere((m) => m['_localId'] == localId));
    }
  }

  void _markStatus(String localId, String status, {String? error}) {
    final i = _pending.indexWhere((m) => m['_localId'] == localId);
    if (i == -1 || !mounted) return;
    setState(() {
      _pending[i]['_status'] = status;
      if (status == 'failed') {
        _pending[i]['_error'] = error ?? '发送失败';
      } else {
        _pending[i].remove('_error');
      }
    });
  }

  /// 用新到的服务端消息把手上的"已发送"本地占位交出去。
  ///
  /// 在 `_loadNewest` 与 `_poll` 的合并处调用：把"本次重拉/轮询新出现、且是自己发的"
  /// 消息，与本地 `sent` 占位按 FIFO 一一对应地抵消。本地占位永远比服务端消息"新"，
  /// 所以 FIFO 成立；`sending`/`failed` 的占位不动（前者还在途中，后者要留给用户重发）。
  /// 这样无论是"重拉带回真身"还是"重拉返回旧页、靠轮询补上"，都会且只会收敛成一条。
  /// 由调用方在 `setState` 内调用（只做集合变更）。
  void _dropCoveredSentPending(List<Map<String, dynamic>> appeared) {
    var mine = appeared.where((e) => e['isMine'] == true).length;
    if (mine == 0) return;
    final kept = <Map<String, dynamic>>[];
    for (final m in _pending) {
      if (mine > 0 && m['_status'] == 'sent') {
        mine--;
        continue;
      }
      kept.add(m);
    }
    if (kept.length != _pending.length) {
      _pending
        ..clear()
        ..addAll(kept);
    }
  }

  List<Map<String, dynamic>> _asItems(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// 滚到底部：reverse 列表的底部即 offset 0（最新消息）
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtl.hasClients) return;
      _scrollCtl.jumpTo(0);
    });
  }

  /// 保持当前阅读位置：reverse 列表在底部插入内容时，按内容高度增量补偿偏移
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
    return PopScope(
      // 有发送失败的消息时拦一次返回：失败内容只存在本次会话，退出即丢失
      canPop: !_hasFailedMessage,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showConfirmDialog(
          context,
          title: '有发送失败的消息',
          message: '失败的消息只在本次会话中保留，退出后将丢失。确定退出？',
          confirmText: '退出',
          cancelText: '留下',
          danger: true,
        );
        if (leave == true && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
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
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty && _pending.isEmpty) {
      return const LoadingView();
    }
    if (_error != null && _items.isEmpty && _pending.isEmpty) {
      return PageErrorWidget(message: _error!, onRetry: _loadNewest);
    }
    if (_items.isEmpty && _pending.isEmpty) {
      return const EmptyView(
        icon: Icons.chat_bubble_outline,
        text: '还没有消息，发送第一条吧',
      );
    }

    // 按时间顺序（旧 → 新）合并：服务端消息 + 本地待发消息
    final all = <Map<String, dynamic>>[..._items, ..._pending];

    // reverse：以底部（最新）为锚点，向上加载旧消息不会顶动可视区
    return ListView.builder(
      controller: _scrollCtl,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      itemCount: all.length + 1,
      itemBuilder: (context, index) {
        // reverse 下 index 0 在视觉最底部 → 最新消息；末尾是"加载更早"头部
        if (index == all.length) return _buildOlderHeader();
        final item = all[all.length - 1 - index];
        return _MessageBubble(
          item: item,
          onFailedTap: item['_status'] == 'failed'
              ? () => _showFailedActions(item)
              : null,
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
            IconButton(
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

/// 单条消息气泡：自己发的靠右（头像在右），对方的靠左（头像在左）
class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> item;

  /// 发送失败时点击叹号的处理（弹「重新发送 / 删除」）；非失败态为 null
  final VoidCallback? onFailedTap;

  const _MessageBubble({required this.item, this.onFailedTap});

  /// 气泡头像：用通用组件 [UserAvatar]（默认点击进入该用户个人空间）
  Widget _avatar(String uid, String nickname) {
    if (uid.isEmpty) return const SizedBox(width: 32);
    return UserAvatar(uid: uid, nickname: nickname, radius: 16);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMine = item['isMine'] == true;
    final bbcode = item['bbcode'] as String? ?? '';
    final time = item['time'] as String? ?? '';
    final senderUid = item['senderUid'] as String? ?? '';
    final senderName = item['senderName'] as String? ?? '';
    final status = item['_status'] as String?;

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
            _avatar(senderUid, senderName),
            const SizedBox(width: 8),
          ] else ...[
            // 固定占位：状态指示器出现/消失不改变气泡可用宽度，
            // 避免"发送中→发送成功"过渡时气泡因 LayoutBuilder 可用宽变化而横向抖动
            _SendStatusIndicator(
              status: status,
              error: item['_error'] as String? ?? '',
              onFailedTap: onFailedTap,
            ),
            const SizedBox(width: 6),
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
                      // 固定占位：本地"发送中"气泡与服务端气泡高度一致，
                      // 避免替换（本地占位 → 服务端消息）时列表因高度变化而纵向抖动
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
          // 自己发的：头像在气泡右侧（与对方镜像）
          if (isMine) ...[
            const SizedBox(width: 8),
            _avatar(senderUid, senderName),
          ],
        ],
      ),
    );
  }
}

/// 自己的消息左侧的固定状态槽：转圈（发送中）／叹号（失败，点击弹操作）／空。
///
/// 槽位尺寸恒定，不随状态出现或消失——否则 `Flexible` 分给气泡的可用宽会变，
/// 气泡在"发送中→发送成功"过渡时会左右抖动。
class _SendStatusIndicator extends StatelessWidget {
  final String? status;
  final String error;
  final VoidCallback? onFailedTap;

  const _SendStatusIndicator({
    required this.status,
    required this.error,
    this.onFailedTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget child;
    if (status == 'sending') {
      child = const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (status == 'failed') {
      child = Tooltip(
        message: error.isNotEmpty ? '$error（点击重发或删除）' : '发送失败，点击重发或删除',
        child: InkWell(
          onTap: onFailedTap,
          borderRadius: BorderRadius.circular(12),
          child: Icon(Icons.error_outline, size: 18, color: cs.error),
        ),
      );
    } else {
      child = const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SizedBox(width: 20, height: 20, child: Center(child: child)),
    );
  }
}
