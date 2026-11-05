part of 'pm_chat_page.dart';

/// 相邻消息超过该间隔才显示时间分隔（与微信聊天一致）
const _kPmTimeSep = Duration(minutes: 5);

/// 发送、本地占位与页面主体构建。
extension on _PmChatPageState {
  Future<void> _send() async {
    final text = _inputCtl.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    // 乐观更新：先本地插入一条"发送中"气泡，再真正提交
    final localId = 'local_${DateTime.now().microsecondsSinceEpoch}';
    // 自己发的消息也带头像：占位期间先用自己的 uid 渲染（服务端消息同样给该字段）
    final myUid = context.read<AuthProvider>().uid;
    _setState(() {
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
        // 错误文案可能很长（服务端返回的消息 / 含换行），整块可滚动：
        // 内容短时贴合，超出底部面板高度时纵向滚动，避免 RenderFlex 溢出
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 8),
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
      ),
    );
    if (!mounted) return;
    if (action == 'retry') {
      _submitLocal(localId, item['bbcode'] as String? ?? '');
    } else if (action == 'delete') {
      _setState(() => _pending.removeWhere((m) => m['_localId'] == localId));
    }
  }

  void _markStatus(String localId, String status, {String? error}) {
    final i = _pending.indexWhere((m) => m['_localId'] == localId);
    if (i == -1 || !mounted) return;
    _setState(() {
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
  /// 由调用方在 `_setState` 内调用（只做集合变更）。
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

    // reverse：以底部（最新）为锚点，向上加载旧消息不会顶动可视区。
    // 外层用 ConstrainedBox 撑满视口高度，使消息不足一屏时像微信那样**顶部对齐**
    // （纯 reverse ListView 在内容不足时会贴底，空出上方大片空白）。
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          controller: _scrollCtl,
          reverse: true,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 视觉顶部：加载更早消息 / "没有更早的消息了"
                  _buildOlderHeader(),
                  ..._buildMessageRows(all),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 构造消息行，并在时间跨度较大的相邻消息之间插入居中时间条。
  ///
  /// 首条消息总是显示时间；之后仅当与上一条的时间差 ≥ [_kPmTimeSep]
  /// （或上一条时间不可解析）时再显示，避免密集对话被时间条打断。
  List<Widget> _buildMessageRows(List<Map<String, dynamic>> all) {
    final now = DateTime.now();
    final rows = <Widget>[];
    DateTime? prev;
    for (final item in all) {
      final t = _parsePmTime(item['time'] as String? ?? '');
      final needSep =
          t != null &&
          (prev == null ||
              t.difference(prev).inSeconds.abs() >= _kPmTimeSep.inSeconds);
      if (needSep) rows.add(_buildTimeSeparator(_formatPmTime(t, now)));
      rows.add(
        PmMessageBubble(
          item: item,
          onFailedTap: item['_status'] == 'failed'
              ? () => _showFailedActions(item)
              : null,
        ),
      );
      if (t != null) prev = t;
    }
    return rows;
  }

  Widget _buildTimeSeparator(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// 解析 Discuz 消息时间（`span[title]`，如 `2026-10-2 16:38`）
  DateTime? _parsePmTime(String raw) {
    final m = RegExp(
      r'(\d{4})-(\d{1,2})-(\d{1,2})[ T](\d{1,2}):(\d{2})',
    ).firstMatch(raw);
    if (m == null) return null;
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
    );
  }

  /// 时间条文案：当天只显示时分；昨天 / 一周内 / 同年 / 跨年逐级补全日期
  String _formatPmTime(DateTime t, DateTime now) {
    final hm =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final day = DateTime(t.year, t.month, t.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return hm;
    if (diff == 1) return '昨天 $hm';
    if (diff > 1 && diff < 7) return '${_weekdayLabel(t.weekday)} $hm';
    if (t.year == now.year) return '${t.month}月${t.day}日 $hm';
    return '${t.year}年${t.month}月${t.day}日 $hm';
  }

  String _weekdayLabel(int weekday) {
    const labels = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return labels[weekday - 1];
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
    // 迷你编辑器：与帖子页共用同一套内核/动作分发；私信无标题、无附件，
    // 图片走 MT 图床（工具栏默认项见 kMiniToolbarDefaults[pm]）。
    return MiniEditorBar(
      contentCtl: _inputCtl,
      toolbarContext: MiniToolbarContext.pm,
      hintText: '发送消息（支持 BBCode）',
      onSubmit: _send,
      onMtImage: _showMtImage,
    );
  }

  /// 私信图片：直接插入 MT 图床外链 `[img]`（私信无论坛附件上传）
  void _showMtImage() {
    showMtImageSheet(
      context,
      hosting: _mtImageHosting,
      onInsert: (bbcode) => _inputCtl.wrapInline('', '', ' $bbcode '),
    );
  }
}
