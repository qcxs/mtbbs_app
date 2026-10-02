import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mtbbs/api/forum/search/export.dart' as search_api;
import 'package:mtbbs/controllers/thread_list_controller.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/widgets/common/page_actions.dart';
import 'package:mtbbs/widgets/thread/thread_grid.dart';

/// 站内搜索结果页
///
/// 由 `/search` 页的「站内搜索」入口进入，也可在页内直接改词重搜。
/// 列表复用 [ThreadGrid]，数据来自 `search.php`：
/// 首次请求拿到 `searchId`，后续翻页回传该 id（Discuz 靠它翻页）。
///
/// 站点对搜索有限流（`searchctrl` / `maxspm`，见 `docs/18`），触发时服务端返回
/// 消息页；这里识别为"搜索过于频繁"，展示专门提示并倒计时禁用重试。
class SearchResultPage extends StatefulWidget {
  /// 初始搜索关键词
  final String keyword;

  const SearchResultPage({super.key, required this.keyword});

  @override
  State<SearchResultPage> createState() => _SearchResultPageState();
}

class _SearchResultPageState extends State<SearchResultPage> {
  late final TextEditingController _inputCtrl;
  final _focusNode = FocusNode();
  late final ThreadListController _listCtrl;

  /// 当前关键词（重搜时更新；fetchFn 闭包在调用时读取）
  late String _keyword;

  /// Discuz 搜索结果会话 id：首次请求后拿到，后续翻页复用
  String? _searchId;

  /// 是否处于"搜索过于频繁"限流态
  bool _rateLimited = false;

  /// 限流剩余等待秒数（>0 时禁用重试）
  int _retryAfter = 0;
  Timer? _countdown;

  @override
  void initState() {
    super.initState();
    _keyword = widget.keyword;
    _inputCtrl = TextEditingController(text: widget.keyword);
    _listCtrl = ThreadListController(
      fetchFn: ({required int page}) async {
        final r = await search_api.searchThreads(
          ApiService().dio,
          keyword: _keyword,
          page: page,
          searchId: _searchId,
        );
        // 首次搜索后缓存 searchid，供后续翻页使用
        _searchId ??= r['searchId'] as String?;
        return r;
      },
    );
    _listCtrl.addListener(_onCtrlChanged);
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _listCtrl.removeListener(_onCtrlChanged);
    _inputCtrl.dispose();
    _focusNode.dispose();
    _listCtrl.dispose();
    super.dispose();
  }

  // ==================== 限流识别 ====================

  void _onCtrlChanged() {
    if (!mounted) return;
    switch (_listCtrl.state) {
      case LoadState.loaded:
        // 搜索成功 → 退出限流态（限流只可能发生在"发起新搜索"这一步）
        if (_rateLimited) setState(() => _rateLimited = false);
      case LoadState.error:
        final secs = _parseRetrySeconds(_listCtrl.errorMessage ?? '');
        if (secs != null) {
          setState(() {
            _rateLimited = true;
            _retryAfter = secs;
          });
          _startCountdown();
        } else if (_rateLimited) {
          // 非限流错误（网络/解析等）→ 交回通用错误态
          setState(() => _rateLimited = false);
        }
      case LoadState.initial:
      case LoadState.loading:
        break;
    }
  }

  /// 从服务端文案解析需等待秒数；非限流文案返回 null。
  ///
  /// 对应 Discuz 两条消息（`lang_message.php`）：
  /// - `search_ctrl`     「抱歉，您在 {N} 秒内只能进行一次搜索」→ N
  /// - `search_toomany`  「…每分钟…搜索请求 {N} 次，请稍候再试」→ 按分钟粒度取 60s
  int? _parseRetrySeconds(String msg) {
    if (msg.isEmpty) return null;
    final m = RegExp(r'(\d+)\s*秒内').firstMatch(msg);
    if (m != null) return int.tryParse(m.group(1)!) ?? 10;
    if (msg.contains('搜索请求') || msg.contains('稍候再试') || msg.contains('每分钟')) {
      return 60;
    }
    return null;
  }

  /// ThreadListController 把 API 的失败包成 `Exception(msg)`，展示前去掉前缀
  String _cleanMsg(String raw) {
    const prefix = 'Exception: ';
    return raw.startsWith(prefix) ? raw.substring(prefix.length) : raw;
  }

  void _startCountdown() {
    _countdown?.cancel();
    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _retryAfter--;
        if (_retryAfter <= 0) {
          _retryAfter = 0;
          t.cancel();
        }
      });
    });
  }

  void _retry() {
    _countdown?.cancel();
    setState(() {
      _rateLimited = false;
      _retryAfter = 0;
    });
    _listCtrl.loadInitial();
  }

  // ==================== 动作 ====================

  Future<void> _submit(String raw) async {
    final kw = raw.trim();
    if (kw.isEmpty) return;
    _focusNode.unfocus();
    // 同词重搜无意义（除非上次失败），直接返回
    if (kw == _keyword && _listCtrl.state != LoadState.error) return;

    setState(() => _keyword = kw);
    _searchId = null; // 换词 → 丢弃旧 searchid，重新发起搜索
    await _listCtrl.loadInitial();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: cs.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: TextField(
          controller: _inputCtrl,
          focusNode: _focusNode,
          textInputAction: TextInputAction.search,
          onSubmitted: _submit,
          decoration: const InputDecoration(
            hintText: '搜索帖子...',
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 8),
          ),
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, size: 20),
            tooltip: '搜索',
            onPressed: () => _submit(_inputCtrl.text),
          ),
          // 仿照帖子页：刷新 + 在浏览器中打开（用 searchid，避免重新搜索）/ 复制链接
          PageActions(
            url: search_api.searchPageUrl(
              keyword: _keyword,
              searchId: _searchId,
              page: _listCtrl.page,
            ),
            // 用 refresh 而非 loadInitial：保留 searchid，刷新复用同一次搜索会话，
            // 不会在服务端新建搜索（避免触发搜索频率限制）
            onRefresh: () => _listCtrl.refresh(),
            copyLabel: '复制搜索链接',
          ),
        ],
      ),
      body: _rateLimited ? _buildRateLimit(cs) : _buildResults(),
    );
  }

  Widget _buildResults() {
    return ThreadGrid(
      controller: _listCtrl,
      highlight: _keyword,
      emptyText: '没有找到匹配结果',
      emptyIcon: Icons.search_off,
    );
  }

  /// 限流提示：说明 + 剩余等待秒数倒计时，期间禁用重试
  Widget _buildRateLimit(ColorScheme cs) {
    final waiting = _retryAfter > 0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_bottom, size: 48, color: cs.outlineVariant),
            const SizedBox(height: 12),
            Text('搜索过于频繁', style: TextStyle(fontSize: 15, color: cs.onSurface)),
            const SizedBox(height: 6),
            Text(
              _cleanMsg(_listCtrl.errorMessage ?? '请稍后再试'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: waiting ? null : _retry,
              icon: Icon(
                waiting ? Icons.timer_outlined : Icons.refresh,
                size: 16,
              ),
              label: Text(waiting ? '请 $_retryAfter 秒后重试' : '重试'),
            ),
          ],
        ),
      ),
    );
  }
}
