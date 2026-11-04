part of 'api_service.dart';

/// 浏览器默认 Accept（模拟浏览器访问时使用）
const String _browserAccept =
    'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8';

/// 客户端构建与请求头处理 —— 创建 Dio、注入拦截器、剔除「浏览方式」Cookie。
extension on ApiService {
  /// 构建绑定指定 baseUrl + CookieJar 的 Dio（含全部拦截器）。
  ///
  /// 全局 `dio` 与跨站点作用域 Dio（见 `scopedDio`）共用同一套拦截器逻辑，
  /// 只有 baseUrl / CookieJar 不同 —— 这样"cookie 绑定在单例上"的限制被解开。
  /// [isGlobal] 标记"这个 Dio 是否就是全局 `dio`" —— 只有它的罐 / baseUrl 会
  /// 在切账号、切站点时被替换，恢复流程需要取实时值。
  Dio _createDio(String baseUrl, CookieJar jar, {bool isGlobal = false}) {
    final d = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        // 默认 UA 为 PC 版（Discuz 按 UA 返回不同模板）；
        // 个别接口（导读/版块/我的帖子）按需用 Options 覆盖为站点配置 UA
        headers: {
          // 功能性头：UA 决定 Discuz 返回哪套模板，
          // X-Requested-With 决定是否按 AJAX 格式返回（去掉会拿到整页 HTML）
          'User-Agent': Site.uaPc,
          'X-Requested-With': 'XMLHttpRequest',
        },
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        responseDecoder: (bytes, options, responseBody) {
          try {
            String? charset;
            final ct = responseBody.headers['content-type']?.join(';');
            if (ct != null) {
              final m = RegExp(
                r'charset=([^;\s]+)',
                caseSensitive: false,
              ).firstMatch(ct);
              if (m != null) charset = m.group(1)!.toLowerCase();
            }
            // 响应头指定了编码 → 按指定编码解码
            if (charset != null && !['utf-8', 'utf8'].contains(charset)) {
              if (['gbk', 'gb2312'].contains(charset)) {
                return gbk.decode(bytes);
              }
              final encoding = Encoding.getByName(charset);
              if (encoding != null) return encoding.decode(bytes);
            }
            // 未指定编码 → 先试 UTF-8，若产生替换字符则试 GBK
            final utf8Result = utf8.decode(bytes, allowMalformed: true);
            if (charset == null && utf8Result.contains('\uFFFD')) {
              try {
                final gbkResult = gbk.decode(bytes);
                if (!gbkResult.contains('\uFFFD')) return gbkResult;
              } catch (_) {}
            }
            return utf8Result;
          } catch (_) {
            return utf8.decode(bytes, allowMalformed: true);
          }
        },
      ),
    );

    // 顺序有意义：CookieManager 先把罐里的 Cookie 合成请求头，过滤器才能从里面
    // 摘掉「浏览方式」Cookie
    d.interceptors.add(CookieManager(jar));
    d.interceptors.add(_browseModeFilter);

    // 统一日志 + 错误处理拦截器
    d.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.extra['_start'] = DateTime.now().millisecondsSinceEpoch;
          // 浏览器仿真头按**目标站点**取开关：全局 Dio 与跨站作用域 Dio 共用，
          // 不再依赖切站时 push 的模块变量（见 docs/04 设置分层）。
          final host = Uri.tryParse(options.baseUrl)?.host ?? '';
          final enabled = SettingsRepository.instance
              .site(host)
              .network
              .simulateBrowserHeaders;
          if (enabled) {
            options.headers['Referer'] = options.baseUrl;
            options.headers['Accept'] = _browserAccept;
          } else {
            options.headers.remove('Referer');
            options.headers.remove('Accept');
          }
          final path = options.path;
          final method = options.method;
          final qp = options.queryParameters;
          // 查询参数仅显示非空值，且太长时截断
          final queryStr = qp.entries
              .where((e) => e.value != null && e.value.toString().isNotEmpty)
              .map((e) => '${e.key}=${e.value}')
              .join('&');
          final fullPath = queryStr.isNotEmpty ? '$path?$queryStr' : path;
          AppLogger.i('DIO', '$method $fullPath');
          handler.next(options);
        },
        onResponse: (response, handler) async {
          final path = response.requestOptions.path;
          final status = response.statusCode ?? 0;
          final size = (response.data as String?)?.length ?? 0;
          final start = response.requestOptions.extra['_start'] as int?;
          final elapsed = start != null
              ? DateTime.now().millisecondsSinceEpoch - start
              : 0;
          AppLogger.i(
            'DIO',
            '$path → $status (${formatBytes(size)}, ${elapsed}ms)',
          );
          // 通用拦截页（人机验证 / 防火墙）：交由注入的处理器恢复，成功后重放。
          //
          // 全局 Dio 的罐 / baseUrl 在切账号、切站点后会被换掉（见
          // switchToAccount / switchSite），这里必须取**实时值**：上面闭包捕获的
          // 只是创建时的快照，用它会把自解 cookie 写进已被替换的旧罐、或按旧站点
          // 域写入 —— 症状是"验证过了还是被拦"，且因为自解返回成功而不再回退
          // WebView。作用域 Dio 的二者创建后不变，直接用捕获值。
          final liveJar = isGlobal ? (activeCookieJar ?? jar) : jar;
          final liveBaseUrl = isGlobal ? d.options.baseUrl : baseUrl;
          if (await _recoverFromInterstitial(
            response,
            client: d,
            jar: liveJar,
            baseUrl: liveBaseUrl,
            isGlobal: isGlobal,
          )) {
            try {
              handler.resolve(await d.fetch(response.requestOptions));
              return;
            } catch (e) {
              AppLogger.w('DIO', '$path 拦截页重放失败: $e');
            }
          }
          handler.next(response);
        },
        onError: (error, handler) {
          final path = error.requestOptions.path;
          if (error.response != null) {
            final status = error.response!.statusCode ?? 0;
            final size = (error.response!.data as String?)?.length ?? 0;
            if (status == 403) {
              AppLogger.w('DIO', '$path → 403 可能需要重新登录');
            } else if (status == 404) {
              AppLogger.w('DIO', '$path → 404 ($size)');
            } else if (status >= 500) {
              AppLogger.e('DIO', '$path → $status 服务器错误');
            } else {
              AppLogger.w('DIO', '$path → $status ($size)');
            }
          } else {
            AppLogger.e('DIO', '$path 网络错误: ${error.message}');
          }
          handler.next(error);
        },
      ),
    );

    // 请求级「浏览模式」覆盖：仅在处于覆盖态（探针一次运行 / MCP 单次调用）时，
    // 把**每个请求**的 UA 改写为覆盖值 —— 这样"不显式设站点 UA 的接口"
    // （帖子详情/排行/在线/圈子/留言板…）也会一起换成指定模板，
    // 从而让"换 UA 复测所有 API"成立。无覆盖时完全不干预（默认 PC UA 保持）。
    d.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (browseModeOverrideActive()) {
            options.headers['User-Agent'] = resolveRequestUserAgent();
          }
          handler.next(options);
        },
      ),
    );

    return d;
  }

  /// 从请求头里摘掉站点「浏览方式」Cookie（`{前缀}_mobile`），避免它盖过 App 的
  /// 「浏览模式」。
  ///
  /// Discuz 的优先级是 **`*_mobile` Cookie 高于 UA**：站点"该页面无手机版"提示里的
  /// 「继续访问电脑版」链接（`…&mobile=no`）会写下 `{前缀}_mobile=no`，此后**该罐内
  /// 所有请求**都被强制按 PC 模板返回，UA 完全不参与决策。实测同一手机 UA、同一 URL：
  /// 罐里没有它 → 173.5 KB 移动卡片；有它 → 89.0 KB PC 表格。
  ///
  /// 症状之所以"怪"：重新登录不会清它、`Max-Age` 还会被反复续期（表现为「移动版」
  /// 永久失效）；CookieJar 按账号隔离（`cookies/{host}/{账号}/`），所以换一个账号
  /// 就正常。
  ///
  /// App 的「浏览模式」是显式设置，不该被一条历史遗留的服务端偏好悄悄覆盖。
  /// 只改本次请求的头、不删罐里的数据 —— 罐里那条会自然过期（`Max-Age=3600`），
  /// 而只要不发送它，站点就回到按 UA 决策。
  void _dropBrowseModeCookie(RequestOptions options) {
    final key = options.headers.keys.firstWhere(
      (k) => k.toLowerCase() == HttpHeaders.cookieHeader,
      orElse: () => '',
    );
    if (key.isEmpty) return;
    final raw = options.headers[key];
    if (raw is! String || raw.isEmpty) return;

    final parts = raw.split(';');
    final kept = parts
        .where(
          (p) => !p.trim().split('=').first.endsWith(kBrowseModeCookieSuffix),
        )
        .toList();
    if (kept.length == parts.length) return;

    // 与 CookieManager 的写法保持一致：空则置 null（Dio 会省略该头）
    options.headers[key] = kept.isEmpty
        ? null
        : kept.map((p) => p.trim()).join('; ');
    AppLogger.i('DIO', '已剔除请求中的浏览方式 Cookie（它会强制 PC 模板）');
  }
}
