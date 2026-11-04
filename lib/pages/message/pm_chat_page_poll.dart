part of 'pm_chat_page.dart';

/// 轮询间隔。Discuz 无增量接口，只能整页重拉，间隔即请求量：
/// 5s 约 720 次/小时，足以触发站点 WAF 的频次限制（403），故放宽到 15s。
const Duration _kPollInterval = Duration(seconds: 15);

/// 连续失败后的退避阶梯：连续第 n 次失败，下一轮推迟 `_kBackoffSteps[n-1]`
/// （超出取末项）。成功一次即复位，避免偶发超时把间隔永久拉长。
const List<Duration> _kBackoffSteps = [
  Duration(seconds: 30),
  Duration(seconds: 60),
  Duration(seconds: 120),
];

/// 判定"用户是否已在底部"的像素阈值：超出则不因新消息自动滚屏（避免打断看历史）
/// （reverse 列表下底部即 offset 0，故直接比较 pixels）
const double _kNearBottomThreshold = 80;

/// 自动轮询 —— 自调度定时器、失败退避与限流暂停。
extension on _PmChatPageState {
  void _startPolling() {
    _pollActive = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    // 限流暂停期间不排下一轮，等手动刷新解除
    if (_pollPausedReason != null) return;
    _scheduleNextPoll(_nextPollDelay());
  }

  void _stopPolling() {
    _pollActive = false;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// 用"跑完再排下一轮"的自调度延时替代 `Timer.periodic`：
  /// 只有这样才能让失败按 [_kBackoffSteps] 退避，且请求耗时超过间隔时
  /// 不会像 periodic 那样积压并发请求。
  void _scheduleNextPoll(Duration delay) {
    if (!_pollActive || _pollPausedReason != null) return;
    _pollTimer?.cancel();
    _pollTimer = Timer(delay, () async {
      await _poll();
      if (mounted) _scheduleNextPoll(_nextPollDelay());
    });
  }

  Duration _nextPollDelay() {
    if (_pollFailures <= 0) return _kPollInterval;
    // 连续失败次数超出阶梯长度时停在同一档（120s）
    final i = _pollFailures > _kBackoffSteps.length
        ? _kBackoffSteps.length - 1
        : _pollFailures - 1;
    return _kBackoffSteps[i];
  }

  /// 记录一次轮询失败：按阶梯退避；403/429（站点限流）直接暂停自动刷新。
  ///
  /// 被限流后仍按原频率重试只会不断延长封禁窗口，所以必须停下，
  /// 把恢复时机交还用户（AppBar 刷新 / 重进页面）。
  void _notePollFailure({int? statusCode, Object? error}) {
    _pollFailures++;
    if (statusCode == 403 || statusCode == 429) {
      _pollPausedReason = '请求过于频繁，已暂停自动刷新，点右上角刷新可继续';
      _pollTimer?.cancel();
      _pollTimer = null;
      AppLogger.w('PAGE', 'PmChatPage 被限流（HTTP $statusCode），暂停自动刷新');
      if (mounted) {
        showToast(_pollPausedReason!, duration: const Duration(seconds: 4));
      }
      return;
    }
    AppLogger.w(
      'PAGE',
      'PmChatPage 轮询失败（连续 $_pollFailures 次）：$error，'
          '${_nextPollDelay().inSeconds}s 后重试',
    );
  }

  /// 表情元数据只在本页尝试一次。
  ///
  /// 原实现在每轮轮询里都调 [EmojiService.load]，而失败时 `loaded` 仍为 false，
  /// 缓存缺失或被拦截时会每轮多打一次 `common_smilies_var.js`，与消息请求
  /// 叠加更容易触发限流。
  Future<void> _ensureEmojiOnce() async {
    if (_emojiRequested) return;
    _emojiRequested = true;
    try {
      await EmojiService().load();
    } catch (e) {
      AppLogger.w('PAGE', 'PmChatPage 表情加载失败，本页不再重试: $e');
    }
  }

  /// 轮询最新一页：把新增的消息追加到列表尾部
  ///
  /// 与首屏/发送复用同一接口，靠 pmid 去重；拉到新消息时，只有用户本来就在
  /// 底部才自动滚屏（否则正在看历史时会被打断）。
  Future<void> _poll() async {
    if (_polling || _loading || _loadingOlder || _sending || !mounted) return;
    // 限流暂停 / 首屏或刷新在途时不轮询（避免同一页面重复整页请求）
    if (_pollPausedReason != null || _loadNewestInFlight != null) return;
    // 页面被其他路由盖住（如从聊天页进了用户主页）时不轮询，回来再继续
    if (ModalRoute.of(context)?.isCurrent != true) return;
    _polling = true;
    final wasNearBottom = _isNearBottom();
    final oldMax = _scrollCtl.hasClients
        ? _scrollCtl.position.maxScrollExtent
        : 0.0;
    try {
      await _ensureEmojiOnce();
      final result = await pm_api.getPmView(
        ApiService().dio,
        touid: widget.touid,
      );
      if (!mounted) return;
      if (result['success'] != true) {
        _notePollFailure(error: result['message'] as String? ?? '轮询失败');
        return;
      }
      _pollFailures = 0;
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
      _setState(() {
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
    } on DioException catch (e) {
      // 失败不弹窗打扰（403/429 除外：会提示已暂停自动刷新），按阶梯退避重试
      _notePollFailure(statusCode: e.response?.statusCode, error: e);
    } catch (e) {
      _notePollFailure(error: e);
    } finally {
      _polling = false;
    }
  }

  bool _isNearBottom() {
    if (!_scrollCtl.hasClients) return true;
    // reverse 列表：offset 0 即最新消息（底部）
    return _scrollCtl.position.pixels <= _kNearBottomThreshold;
  }
}
