import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/core/app/cookie_sync.dart';
import 'package:mtbbs/core/app/page_helper.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/app/session_registry.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/pages/verify/verify_browser_page.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';
import 'package:mtbbs/widgets/layout/window_title_bar.dart';

/// 全局人机验证守门器 —— "站点返回的不是论坛页"时的统一恢复入口。
///
/// 由 Dio 拦截器调用（[ApiService.interstitialHandler] 注入），流程：
/// 1. 弹出全屏验证浏览器（仿 toast 的全局能力，与当前页面无关）
/// 2. 用户在该浏览器里通过验证（纯 JS 挑战会自动通过，验证码需手动完成）
/// 3. **以"回流 cookie 后用相同 URL/UA 重发请求能拿到论坛页"为唯一判据**，
///    判定通过后自动关闭弹窗，Dio 拦截器随即重放原请求
///
/// 刻意不做厂商适配：判断依据是"这不是一个能用的论坛页"（见
/// [looksLikeInterstitialPage]），因此对任何来源的人机验证都成立。
class VerificationGate {
  VerificationGate._();

  static final VerificationGate instance = VerificationGate._();

  /// 是否启用 —— 由 main.dart 绑定到设置项（关闭后完全不介入）
  bool Function() isEnabled = () => true;

  /// 当前账号的登录 cookie 串 —— 由 main.dart 绑定到 `AuthProvider`。
  ///
  /// 验证页**只注入它**（而不是整个 CookieJar）：罐里可能存着服务端已判过期的
  /// 防护 cookie，灌进验证页会让挑战继续拿到旧值（见 docs/07 #73）。
  String Function()? loginCookieString;

  /// 失败冷却：用户取消或超时后，短时间内不再弹窗，避免连续骚扰
  static const Duration _failureCooldown = Duration(seconds: 60);

  /// 单飞：验证进行中时，后续失败请求共用同一次结果
  Completer<bool>? _inFlight;

  DateTime _lastFailureAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 本次验证的探测上下文 —— 与失败请求保持一致
  InterstitialContext? _probeCtx;
  String _probeUrl = '';
  String? _probeUserAgent;

  /// Dio 拦截器入口。返回 true 表示"已通过验证"。
  Future<bool> handle(RequestOptions options, InterstitialContext ctx) async {
    if (!isEnabled()) return false;

    // 无 UI 上下文（启动早期 / 后台任务 / MCP 服务端请求）→ 无处可弹，直接失败。
    // 不能在这里挂起等待：那些场景没有用户，会把请求无限卡住。
    final nav = rootNavigatorKey.currentState;
    if (nav == null) {
      AppLogger.w('PAGE', '需要人机验证，但当前无可用界面，跳过弹窗');
      return false;
    }
    if (DateTime.now().difference(_lastFailureAt) < _failureCooldown) {
      AppLogger.d('PAGE', '人机验证处于冷却期，暂不弹窗');
      return false;
    }
    final existing = _inFlight;
    if (existing != null) return existing.future;

    final completer = Completer<bool>();
    _inFlight = completer;
    final ok = await _run(
      nav: nav,
      url: options.uri.toString(),
      userAgent: options.headers['User-Agent'] as String?,
      ctx: ctx,
    );
    _inFlight = null;
    if (!completer.isCompleted) completer.complete(ok);
    return ok;
  }

  /// 页面手动入口（错误页的「网页验证」按钮）。
  ///
  /// 自动恢复失败时（例如本地自解写错了地方、或站点改成需要交互式验证），
  /// 用户可以直接打开验证浏览器；验证通过后 cookie 回流到**该 URL 所属站点**
  /// 的罐（跨站点页面回流到它自己的作用域罐，而不是全局活跃罐）。
  ///
  /// 不走冷却期：这是用户显式发起的操作。
  Future<bool> verifyManually({
    required String url,
    String? userAgent,
  }) async {
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return false;
    final ctx = _contextForUrl(url);
    if (ctx == null) {
      AppLogger.w('PAGE', '网页验证：无法确定 $url 所属站点');
      return false;
    }
    final existing = _inFlight;
    if (existing != null) return existing.future;

    final completer = Completer<bool>();
    _inFlight = completer;
    final ok = await _run(
      nav: nav,
      url: url,
      userAgent: userAgent,
      ctx: ctx,
    );
    _inFlight = null;
    if (!completer.isCompleted) completer.complete(ok);
    return ok;
  }

  /// 弹验证页并等待结果（`handle` / `verifyManually` 共用）
  Future<bool> _run({
    required NavigatorState nav,
    required String url,
    required String? userAgent,
    required InterstitialContext ctx,
  }) async {
    _probeCtx = ctx;
    // 探测一律回到"触发拦截的那个地址"，并用同一个 UA —— 与失败请求同源，
    // 避免 cookie 与 UA 绑定导致"浏览器过了、API 还是不行"。
    _probeUrl = url;
    _probeUserAgent = userAgent;
    final cookieString = await _cookieStringFor(ctx);

    var ok = false;
    try {
      AppLogger.i('PAGE', '弹出人机验证：$url');
      final result = await nav.push<bool>(
        MaterialPageRoute<bool>(
          fullscreenDialog: true,
          builder: (_) => WindowChrome(
            child: VerifyBrowserPage(
              url: url,
              userAgent: userAgent ?? Site.uaPc,
              cookieString: cookieString,
              probe: _probePassed,
            ),
          ),
        ),
      );
      ok = result ?? false;
      AppLogger.i('PAGE', '人机验证结束：${ok ? '已通过' : '未通过'}');
    } catch (e) {
      AppLogger.w('PAGE', '人机验证流程异常: $e');
    } finally {
      if (!ok) _lastFailureAt = DateTime.now();
      _probeCtx = null;
    }
    return ok;
  }

  /// 验证页要注入的登录态 cookie 串。
  ///
  /// 全局站点用 `AuthProvider` 的串；跨站点会话从它自己的罐里取（只注入核心
  /// cookie 的过滤在 `syncCookieStringToWebView` 里做，见 docs/07 #73）。
  Future<String> _cookieStringFor(InterstitialContext ctx) async {
    if (ctx.isGlobal) {
      return loginCookieString?.call() ?? '';
    }
    try {
      final uri = Uri.tryParse(ctx.baseUrl);
      if (uri == null) return '';
      final cookies = await ctx.jar.loadForRequest(uri);
      return cookies.map((c) => '${c.name}=${c.value}').join('; ');
    } catch (e) {
      AppLogger.d('PAGE', '读取跨站点会话 cookie 失败: $e');
      return '';
    }
  }

  /// 按 URL 解析出"该用哪个客户端 / 罐 / 站点"。
  InterstitialContext? _contextForUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    final activeJar = ApiService().activeCookieJar;
    if (uri.host == SiteStore.instance.host) {
      if (activeJar == null) return null;
      return InterstitialContext(
        client: ApiService().dio,
        jar: activeJar,
        baseUrl: SiteStore.instance.baseUrl,
        isGlobal: true,
      );
    }
    final session = SessionRegistry.instance.resolve(uri.host);
    final scopedJar = ApiService().scopedJar(
      host: uri.host,
      account: session?.accountName,
    );
    if (session != null && scopedJar != null) {
      return InterstitialContext(
        client: session.dio,
        jar: scopedJar,
        baseUrl: session.baseUrl,
      );
    }
    // 未配置的站点：借全局客户端访问该站点（cookie 按 domain 落活跃罐）
    if (activeJar == null) return null;
    return InterstitialContext(
      client: ApiService().dio,
      jar: activeJar,
      baseUrl: '${uri.scheme}://${uri.host}',
      isGlobal: true,
    );
  }

  /// 探测是否已通过。
  ///
  /// 这是**唯一权威判据**：不看 DOM、不看 cookie 变化，直接回流 WebView 的
  /// cookie 后用相同 URL/UA 重发一次请求 —— 拿到论坛页才算通过。
  /// 与拦截判定互为反面（同一个 [looksLikeInterstitialPage]），天然自洽。
  Future<bool> _probePassed() async {
    final ctx = _probeCtx;
    if (ctx == null || _probeUrl.isEmpty) return false;
    try {
      // 回流到**本次请求所属**的罐（全局会话是活跃罐，跨站点是它自己的作用域罐）。
      final newCookies = await syncWebViewCookiesToJar(
        jar: ctx.jar,
        baseUrl: ctx.baseUrl,
      );
      // 客户端级 cookie 补写到本站点其它罐 —— 仅全局站点：跨站点作用域罐是
      // 长生命周期实例，另写一份会与它们的内存副本互相覆盖（见 docs/27）。
      if (ctx.isGlobal) {
        await ApiService().mirrorToAllJarsForHost(newCookies);
      }
    } catch (e) {
      AppLogger.d('PAGE', '探测前回流 cookie 失败: $e');
    }

    try {
      final resp = await ctx.client.get<String>(
        _probeUrl,
        options: Options(
          headers: {if (_probeUserAgent != null) 'User-Agent': _probeUserAgent},
          // 标记已处理，避免探测自身再次触发弹窗
          extra: {kInterstitialHandledFlag: true},
        ),
      );
      if (resp.statusCode != 200) return false;
      final body = resp.data ?? '';
      if (body.isEmpty) return false;
      if (looksLikeInterstitialPage(body, resp.headers.value('content-type'))) {
        return false;
      }
      return true;
    } catch (e) {
      AppLogger.d('PAGE', '人机验证探测失败: $e');
      return false;
    }
  }
}
