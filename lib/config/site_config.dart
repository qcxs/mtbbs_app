/// 站点配置 — 仅保留常量和数据模型
class SiteConfig {
  SiteConfig._();

  static const String cookieDir = 'cookies';

  /// 默认站点列表（首次运行或重置时使用）
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

  static const String uaAndroid =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  static const String uaPc =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
}
