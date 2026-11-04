part of 'api_service.dart';

/// 拦截页恢复与 Cookie 镜像。
///
/// 具名扩展：`mirrorToAllJarsForHost` 是公开 API，匿名扩展的成员对 import 方不可见。
extension ApiServiceRecovery on ApiService {
  /// 把验证流程新拿到的**客户端级 cookie**（人机验证 / 防火墙）补写到本站点的
  /// **每一个罐**：游客罐 + 其余账号罐。
  ///
  /// 这类 cookie 与登录账号无关（按 IP / UA 下发），而罐按 `{host}/{账号}` 隔离；
  /// 只写活跃罐的话，切账号 / 切游客 / 重启落到别的罐就要重新验证。
  ///
  /// 为什么不是"一个站点共享罐"：那得额外回答三个问题——谁有资格进共享罐（准入）、
  /// 同名时哪个罐的值胜出（优先级）、共享罐何时刷新（服务端只会刷新活跃罐）。
  /// 补写进每个罐，这三个问题都不存在：各自的副本随该罐被激活时由服务端正常刷新。
  /// 代价是**新建账号要多验证一次**。
  ///
  /// [cookies] 取自 `syncWebViewCookiesToJar` 的返回值，已是"活跃罐里原本没有的"
  /// 名字 —— 只含新出现的客户端级 cookie，不会把账号登录态扩散到别的罐。
  Future<void> mirrorToAllJarsForHost(List<Cookie> cookies) async {
    if (cookies.isEmpty) return;
    final uri = Uri.tryParse(SiteStore.instance.baseUrl);
    if (uri == null || uri.host.isEmpty) return;

    // 活跃罐已由回流流程写入，这里只补其它罐
    if (_activeAccount != null) {
      await _mirror(uri, cookies, _guestJar);
    }

    final account = _activeAccount;
    final activeDir = account == null
        ? null
        : (await AppPaths.cookiesDirForAccount(
            _currentHost,
            account,
          )).replaceAll('\\', '/');
    for (final dir in await AppPaths.accountJarDirsForHost(_currentHost)) {
      if (activeDir != null && dir.replaceAll('\\', '/') == activeDir) continue;
      await _mirror(
        uri,
        cookies,
        PersistCookieJar(storage: FileStorage(dir), ignoreExpires: true),
      );
    }
  }

  Future<void> _mirror(Uri uri, List<Cookie> cookies, CookieJar? jar) async {
    if (jar == null) return;
    try {
      await jar.saveFromResponse(uri, cookies);
    } catch (e) {
      AppLogger.w('PAGE', '补写客户端级 cookie 到其它罐失败: $e');
    }
  }

  /// 命中"非论坛页"（人机验证 / 防火墙拦截页）时尝试自动恢复。
  ///
  /// 两级恢复：
  /// 1. **本地自解**——执行挑战页脚本，拿到它写下的 cookie 或它要求跳转的地址，
  ///    与浏览器一样无感（见 [JsChallengeSolver]）；
  /// 2. **人工验证弹窗**——自解不了（滑块 / 点选等交互式验证、脚本结构变化）才
  ///    弹出内置浏览器让用户完成（[VerificationGate]）。
  ///
  /// 返回 true 表示**已通过验证且可以重放本次请求**（打了重放标记）。
  /// 仅 GET 自动重放：写操作（发帖/评论）重放有重复提交风险，验证通过后
  /// 交给用户手动重试。
  Future<bool> _recoverFromInterstitial(
    Response<dynamic> response, {
    required Dio client,
    required CookieJar jar,
    required String baseUrl,
    bool isGlobal = false,
  }) async {
    final options = response.requestOptions;
    if (options.extra[kInterstitialHandledFlag] == true) return false;
    if (response.statusCode != 200) return false;

    final body = response.data;
    if (body is! String || body.isEmpty) return false;
    // Discuz 的 ajax 响应被 `<root><![CDATA[…]]></root>` / `<?xml …?>` 包着，
    // 那是"片段"而不是一个独立页面；WAF 拦截不会包这层壳。
    // 用"是否 CDATA/XML 包装"排除，比按 inajax 参数排除更准 —— 后者会漏掉
    // 同样会被拦截的写操作（发帖/评论）。
    final head = body.trimLeft();
    if (body.contains('<![CDATA[') || head.startsWith('<?xml')) return false;
    if (!looksLikeInterstitialPage(
      body,
      response.headers.value('content-type'),
    )) {
      return false;
    }

    AppLogger.w('DIO', '${options.path} 命中非论坛页（${body.length}B），尝试自动恢复');

    // ① 本地自解（JS 引擎执行挑战页脚本）：成功即与浏览器一样无感
    if (await _solveJsChallengeLocally(
      body,
      options.uri,
      client: client,
      jar: jar,
      baseUrl: baseUrl,
    )) {
      if (options.method != 'GET') {
        AppLogger.i('DIO', '${options.path} 已本地自解验证，但非 GET 请求不自动重放');
        return false;
      }
      AppLogger.i('DIO', '${options.path} 已本地自解验证，重放请求');
      options.extra[kInterstitialHandledFlag] = true;
      return true;
    }

    // ② 自解不了（交互式验证 / 结构变化）→ 交给人工验证弹窗。
    //    把本次请求的客户端 / 罐 / 站点一起传过去：跨站点页面也能验证，
    //    cookie 回流到它自己的罐，而不是"只能回流全局活跃罐故不启用"。
    final recover = interstitialHandler;
    if (recover == null) return false;
    final recovered = await recover(
      options,
      InterstitialContext(
        client: client,
        jar: jar,
        baseUrl: baseUrl,
        isGlobal: isGlobal,
      ),
    );
    if (!recovered) {
      AppLogger.w('DIO', '${options.path} 未通过人机验证，按原样返回');
      return false;
    }
    if (options.method != 'GET') {
      AppLogger.i('DIO', '${options.path} 已通过验证，但非 GET 请求不自动重放');
      return false;
    }
    AppLogger.i('DIO', '${options.path} 已通过验证，重放请求');
    options.extra[kInterstitialHandledFlag] = true;
    return true;
  }

  /// 本地自解 JS 挑战，并让结果生效。
  ///
  /// 两种收尾方式（见 [JsChallengeSolution]）：
  /// - **脚本写了 cookie**（如阿里云 ESA 的 `acw_sc__v2`）：写进当前活跃罐即可。
  ///   同一响应的 `Set-Cookie` 已由 `CookieManager` 落罐（`acw_tc` / `cdn_sec_tc`），
  ///   三者必须配对；**刻意不做跨罐镜像**：`acw_sc__v2` 与"本轮下发的 arg1"绑定，
  ///   复制到别的罐会与那边的 `acw_tc` 错配。
  /// - **脚本要求跳转**（如网宿 WZWS 的 `?wzwschallenge=…`）：用同一个 Dio 把该地址
  ///   请求一次。服务端认可后会 302 回原地址并直接给真实页面，同时把本客户端
  ///  （IP + UA 指纹）标记为已通过——此后普通请求一段时间内不再被挑战，**无需 cookie**。
  ///
  /// 失败（脚本结构变化 / 跳转仍被拦）返回 false，由调用方回退到 WebView。
  Future<bool> _solveJsChallengeLocally(
    String body,
    Uri pageUri, {
    required Dio client,
    required CookieJar jar,
    required String baseUrl,
  }) async {
    final solution = JsChallengeSolver.instance.solve(
      body,
      pageUrl: pageUri.toString(),
    );
    if (solution == null || solution.isEmpty) return false;

    final base = Uri.tryParse(baseUrl);
    if (base == null || base.host.isEmpty) return false;

    if (solution.cookies.isNotEmpty) {
      try {
        await jar.saveFromResponse(
          base,
          solution.cookies.entries
              .map(
                (e) => Cookie(e.key, e.value)
                  ..domain = '.${base.host}'
                  ..path = '/',
              )
              .toList(),
        );
        AppLogger.i('DIO', 'JS 挑战自解：写入 ${solution.cookies.length} 个 cookie');
        return true;
      } catch (e) {
        AppLogger.w('DIO', 'JS 挑战自解 cookie 写入失败: $e');
        return false;
      }
    }

    // 只允许同站点跳转：地址来自挑战页脚本，不能拿它去请求别的主机
    final raw = solution.redirectUrl!;
    final parsed = Uri.tryParse(raw);
    final target = parsed == null
        ? null
        : (parsed.hasScheme ? parsed : base.resolveUri(parsed));
    if (target == null || target.host != base.host) {
      AppLogger.w('DIO', 'JS 挑战自解：忽略跨站跳转 $raw');
      return false;
    }

    try {
      final res = await client.get<String>(
        target.toString(),
        options: Options(
          // 该请求自己也可能被拦，但这里不再递归自解，失败就交给 L2
          extra: {kInterstitialHandledFlag: true},
        ),
      );
      final status = res.statusCode ?? 0;
      if (status < 200 || status >= 400) {
        AppLogger.w('DIO', 'JS 挑战自解：跳转返回 $status');
        return false;
      }
      final text = res.data ?? '';
      if (looksLikeInterstitialPage(text, res.headers.value('content-type'))) {
        AppLogger.w('DIO', 'JS 挑战自解：跳转后仍是拦截页');
        return false;
      }
      AppLogger.i('DIO', 'JS 挑战自解：完成跳转验证（${target.path}）');
      return true;
    } catch (e) {
      AppLogger.w('DIO', 'JS 挑战自解跳转失败: $e');
      return false;
    }
  }
}
