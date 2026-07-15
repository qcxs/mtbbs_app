/// 站点配置 — 支持多域名切换
///
/// 调用方式：`SiteConfig.current.baseUrl` / `SiteConfig.current.forums`
class SiteConfig {
  SiteConfig._();

  /// Cookie 存储相对路径（在应用文档目录下）
  static const String cookieDir = 'cookies';

  /// 当前活跃站点
  static late Site current;

  /// 所有可用站点列表
  static List<Site> sites = [];

  /// 初始化站点列表并设置默认站点
  static void init({int defaultIndex = 0}) {
    current = defaultSites()[defaultIndex];
    sites = defaultSites();
  }

  /// 默认站点列表（首次运行或重置时使用）
  /// 板块/积分等数据由设置守卫在启动时自动从 API 获取。
  static List<Site> defaultSites() => [
    Site(
      name: 'MT论坛',
      baseUrl: 'https://bbs.binmt.cc',
      cdn: 'https://cdn-bbs.mt2.cn',
      loginPagePath: '/member.php?mod=logging&action=login',
      forums: {},
      defaultForumOrder: [],
    ),
  ];

  /// 切换到指定索引的站点
  static void switchTo(int index) {
    if (index >= 0 && index < sites.length) {
      current = sites[index];
    }
  }

  // ==================== 向下兼容的静态别名 ====================
  static String get baseUrl => current.baseUrl;
  static String get cdnUrl => current.cdnUrl;
  static String get loginPagePath => current.loginPagePath;
  static Map<String, String> get forums => current.forums;
  static List<String> get defaultForumOrder => current.defaultForumOrder;
  static String get uaAndroid => Site.uaAndroid;
  static String get uaPc => Site.uaPc;
}

/// 单个站点配置
class Site {
  final String name;
  final String baseUrl;
  final String? cdn;
  final String loginPagePath;
  final Map<String, String> forums;
  final List<String> defaultForumOrder;

  const Site({
    required this.name,
    required this.baseUrl,
    this.cdn,
    required this.loginPagePath,
    required this.forums,
    required this.defaultForumOrder,
  });

  String get host => Uri.parse(baseUrl).host;

  /// CDN 地址，为空时回退到 [baseUrl]
  String get cdnUrl {
    if (cdn != null && cdn!.isNotEmpty) return cdn!;
    // 没有 CDN 时回退到默认站点的 CDN（用户未设置时也能用）
    final def = SiteConfig.defaultSites().cast<Site?>().firstWhere(
      (d) => d?.baseUrl == baseUrl && (d?.cdn?.isNotEmpty == true),
      orElse: () => null,
    );
    if (def != null) return def.cdn!;
    return baseUrl;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'baseUrl': baseUrl,
    if (cdn != null && cdn!.isNotEmpty) 'cdn': cdn,
    'loginPagePath': loginPagePath,
    'forums': forums,
    'defaultForumOrder': defaultForumOrder,
  };

  factory Site.fromJson(Map<String, dynamic> json) => Site(
    name: json['name']?.toString() ?? '',
    baseUrl: json['baseUrl']?.toString() ?? '',
    cdn: json['cdn']?.toString(),
    loginPagePath:
        json['loginPagePath']?.toString() ??
        '/member.php?mod=logging&action=login',
    forums: Map<String, String>.from(json['forums'] as Map? ?? {}),
    defaultForumOrder: List<String>.from(
      json['defaultForumOrder'] as List? ?? [],
    ),
  );

  /// User-Agent
  static const String uaAndroid =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  static const String uaPc =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
}
