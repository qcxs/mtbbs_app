part of 'pm_chat_page.dart';

/// 数据加载 —— 首屏最新页、向上加载更旧页、条目归一化。
extension on _PmChatPageState {
  /// 会话在站内的完整地址，供「在浏览器中打开 / 复制链接」使用
  String get _pageUrl =>
      '${SiteStore.instance.baseUrl}/home.php?mod=space&do=pm&subop=view&touid=${widget.touid}';

  /// 拉取最新一页并替换列表（单飞：在途时复用同一请求）
  ///
  /// 首屏、发送成功后的重拉、下拉/按钮刷新、轮询的"整体重载"都走这里；
  /// 若不单飞，发送与轮询会同时打出两次相同的整页请求，白白加重站点负担。
  Future<void> _loadNewest() {
    return _loadNewestInFlight ??= _doLoadNewest().whenComplete(() {
      _loadNewestInFlight = null;
    });
  }

  /// [_loadNewest] 的实际实现
  ///
  /// 替换 `_items` 与"交出已发送的本地占位"在同一帧内完成（原子交接），避免
  /// "消息消失 / 重复"的一帧。**但只有当重拉确实带回了新消息（出现新 pmid）时
  /// 才交出占位**：Discuz 私信存在"读后写"延迟，发送成功后的首次重拉可能仍返回
  /// 旧页（实测 `totalCount` 已 +1，但条目还是上一页的），此时若照删占位，
  /// 消息就会消失到下一次轮询；保留占位，等轮询拿到真身再收敛。
  Future<void> _doLoadNewest() async {
    final prevPmids = _items.map((e) => e['pmid']).toSet();
    _setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _ensureEmojiOnce();
      final result = await pm_api.getPmView(
        ApiService().dio,
        touid: widget.touid,
      );
      if (!mounted) return;
      if (result['success'] != true) {
        _setState(() {
          _error = result['message'] as String? ?? '加载失败';
          _loading = false;
        });
        return;
      }
      // 成功即解除限流暂停并复位退避，恢复自动刷新
      final resumedFromLimit = _pollPausedReason != null;
      _pollFailures = 0;
      _pollPausedReason = null;
      final items = _asItems(result['items']);
      final appeared = items
          .where((e) => !prevPmids.contains(e['pmid']))
          .toList();
      _setState(() {
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
      // 只在"限流暂停后恢复"时重排轮询；其余情况轮询链自有节奏，
      // 后台态（_pollActive=false）交给 resumed 回调重启
      if (resumedFromLimit && _pollActive) _scheduleNextPoll(_nextPollDelay());
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      AppLogger.w('PAGE', 'PmChatPage load error: $e');
      _setState(() {
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
    _setState(() => _loadingOlder = true);

    try {
      await _ensureEmojiOnce();
      final result = await pm_api.getPmView(
        ApiService().dio,
        touid: widget.touid,
        page: _olderPage,
      );
      if (!mounted) return;
      if (result['success'] != true) {
        showToast(result['message'] as String? ?? '加载更早消息失败');
        _setState(() => _loadingOlder = false);
        return;
      }
      final older = _asItems(result['items']);
      final existing = _items.map((e) => e['pmid']).toSet();
      final fresh = older.where((e) => !existing.contains(e['pmid'])).toList();

      _setState(() {
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
      _setState(() => _loadingOlder = false);
    }
  }
}
