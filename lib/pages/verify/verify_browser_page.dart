import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:mtbbs/core/app/cookie_sync.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';

/// 人机验证弹窗页（全屏模态，由根导航器全局弹出，与当前所在页面无关）。
///
/// 站点返回"不是论坛页"（人机验证 / 防火墙）时，把**失败的那个地址**放进真实
/// WebView 让用户通过验证：
/// - 纯 JS 挑战会自动通过（WebView 自己执行脚本并重载），用户无需操作；
/// - 验证码 / 滑块需要用户手动完成。
///
/// "是否通过"不靠猜 DOM，也不靠 cookie 变化，而是由 [probe] 判定：
/// 回流 cookie 后用相同 URL / UA 重发请求，拿到论坛页才算通过（唯一权威判据）。
/// 通过后自动关闭，Dio 拦截器随即重放原请求。
class VerifyBrowserPage extends StatefulWidget {
  const VerifyBrowserPage({
    super.key,
    required this.url,
    required this.userAgent,
    required this.cookieString,
    required this.probe,
    this.probeInterval = const Duration(seconds: 5),
    this.timeout = const Duration(seconds: 90),
  });

  /// 触发拦截的地址（探测也用它）
  final String url;

  /// WebView 使用的 UA —— 与失败请求保持一致，确保验证拿到的 cookie
  /// 对后续 API 请求同样有效
  final String userAgent;

  /// 当前账号的登录 cookie 串（游客传空串）。
  ///
  /// **只注入它，不注入整个 CookieJar**：罐里可能存着服务端已判过期的防护
  /// cookie（人机验证 / 防火墙，如 `acw_tc` 带 `Max-Age=3600`），把它们灌进
  /// 验证页只会让挑战继续拿到旧值，挑战产生的新值又与旧值同名并存，形成
  /// "每次冷启动都要验证"的死锁（见 docs/07 #73）。
  final String cookieString;

  /// 探测是否已通过（由 `VerificationGate` 提供）
  final Future<bool> Function() probe;

  /// 轮询间隔（安全网）——真正的"通过"通常由 onLoadStop 立刻触发探测，
  /// 这里只是兜住"没有发生页面跳转"的验证方式（如纯 AJAX 完成）
  final Duration probeInterval;

  /// 总超时，超过则判定未完成
  final Duration timeout;

  @override
  State<VerifyBrowserPage> createState() => _VerifyBrowserPageState();
}

class _VerifyBrowserPageState extends State<VerifyBrowserPage> {
  /// 两次探测的最小间隔 —— onLoadStop 可能因重定向/自动重载连续触发，
  /// 探测是一次整页请求，必须节流
  static const Duration _minProbeGap = Duration(milliseconds: 1500);

  InAppWebViewController? _controller;
  Timer? _poll;
  Timer? _deadline;
  bool _probing = false;
  bool _cookiesReady = false;
  bool _finished = false;
  DateTime _lastProbeAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(widget.probeInterval, (_) => unawaited(_probe()));
    _deadline = Timer(
      widget.timeout,
      () => _finish(false, reason: '等待超时，请稍后重试'),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_injectCookies()),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    _deadline?.cancel();
    super.dispose();
  }

  /// 准备验证页的 cookie：**先清空，再只注入登录串**。
  ///
  /// 清空用 `deleteAllCookies()`：按域逐条删在 Android 上删不干净，实测旧的
  /// `acw_sc__v2` 会跨会话存活（docs/07 #71 的坑）。验证页是一次性全屏模态，
  /// 清空 WebView 级 cookie 的代价只是内置浏览器下次打开要重新同步。
  Future<void> _injectCookies() async {
    try {
      await CookieManager.instance().deleteAllCookies();
    } catch (e) {
      AppLogger.w('PAGE', '清空验证浏览器 cookie 失败: $e');
    }
    try {
      await syncCookieStringToWebView(
        widget.cookieString,
        SiteStore.instance.baseUrl,
      );
    } catch (e) {
      AppLogger.w('PAGE', '验证浏览器注入登录 cookie 失败: $e');
    }
    if (mounted) setState(() => _cookiesReady = true);
  }

  /// 探测一次；通过则立即结束
  Future<bool> _probe({bool force = false}) async {
    if (_probing || _finished) return false;
    if (!force && DateTime.now().difference(_lastProbeAt) < _minProbeGap) {
      return false;
    }
    _lastProbeAt = DateTime.now();
    _probing = true;
    try {
      final ok = await widget.probe();
      if (ok) {
        _finish(true);
        return true;
      }
      return false;
    } finally {
      _probing = false;
    }
  }

  void _finish(bool ok, {String? reason}) {
    if (_finished) return;
    _finished = true;
    _poll?.cancel();
    _deadline?.cancel();
    if (!mounted) return;
    Navigator.of(context).pop(ok);
    showToast(ok ? '验证已通过，正在继续' : (reason ?? '未完成验证'));
  }

  Future<void> _manualCheck() async {
    if (_probing) {
      showToast('正在检测…');
      return;
    }
    final ok = await _probe(force: true);
    if (!ok && mounted && !_finished) {
      showToast('尚未检测到通过，请完成页面上的验证');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('站点验证'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: '取消',
          onPressed: () => _finish(false, reason: '已取消验证'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新页面',
            onPressed: () => _controller?.reload(),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: cs.outlineVariant),
        ),
      ),
      body: Column(
        children: [
          _buildHint(cs),
          Expanded(child: _buildWebView()),
        ],
      ),
    );
  }

  Widget _buildHint(ColorScheme cs) {
    return Container(
      width: double.infinity,
      color: cs.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '站点触发了人机验证。请在下方页面完成验证，通过后会自动继续'
              '（纯脚本验证通常无需操作）。',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: _manualCheck, child: const Text('我已完成')),
        ],
      ),
    );
  }

  Widget _buildWebView() {
    if (!_cookiesReady) {
      return const Center(child: CircularProgressIndicator());
    }
    return InAppWebView(
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent: widget.userAgent,
        supportZoom: true,
      ),
      initialUrlRequest: URLRequest(url: WebUri(widget.url)),
      onWebViewCreated: (controller) => _controller = controller,
      // 每次加载完成立刻探测一次：JS 挑战会自动重载到真实页面，
      // 这样能最快确认通过，不必等下一个轮询周期
      onLoadStop: (controller, url) => unawaited(_probe()),
    );
  }
}
