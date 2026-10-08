import 'package:mtbbs/core/app/default_config.dart';

/// 站点配置 — 数据模型 + 默认值委托
class SiteConfig {
  SiteConfig._();

  static const String cookieDir = 'cookies';

  /// 默认站点列表（首次运行或重置时使用）
  /// 优先从 [DefaultConfig] 加载，失败时回退到内嵌硬编码。
  static List<Site> defaultSites() => DefaultConfig.instance.defaultSites;
}

/// 单个站点配置
class Site {
  final String name;
  final String baseUrl;
  final String loginPagePath;
  final Map<String, String> forums;
  final List<String> defaultForumOrder;

  /// 当前站点使用的 User-Agent，空字符串表示使用默认（Android 手机 UA）
  final String userAgent;

  /// 站点头像 URL 模板，为空时使用默认 API 方案
  /// （`{baseurl}/uc_server/avatar.php?uid={uid}&size={size}`），
  /// 见 [resolveAvatarUrl]
  final String? avatarTemplate;

  const Site({
    required this.name,
    required this.baseUrl,
    required this.loginPagePath,
    required this.forums,
    required this.defaultForumOrder,
    this.userAgent = '',
    this.avatarTemplate,
  });

  String get host => Uri.parse(baseUrl).host;

  /// 当前站点的有效 User-Agent
  String get effectiveUserAgent => userAgent.isNotEmpty ? userAgent : uaAndroid;

  /// 是否使用移动端 UA（含 "Mobile" 关键字）
  bool get isMobileUA => effectiveUserAgent.contains('Mobile');

  /// 复制并覆盖字段；不传（null）= 保持不变。显式清空 [avatarTemplate] 用
  /// [clearAvatarTemplate]。
  ///
  /// 站点列表在设置页各处都是"改一个字段、重建整只 [Site]"，手抄字段很容易漏掉
  /// 新加的，统一走这里。
  Site copyWith({
    String? name,
    String? baseUrl,
    String? loginPagePath,
    Map<String, String>? forums,
    List<String>? defaultForumOrder,
    String? userAgent,
    String? avatarTemplate,
    bool clearAvatarTemplate = false,
  }) => Site(
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
    loginPagePath: loginPagePath ?? this.loginPagePath,
    forums: forums ?? this.forums,
    defaultForumOrder: defaultForumOrder ?? this.defaultForumOrder,
    userAgent: userAgent ?? this.userAgent,
    avatarTemplate: clearAvatarTemplate
        ? null
        : (avatarTemplate ?? this.avatarTemplate),
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'baseUrl': baseUrl,
    'loginPagePath': loginPagePath,
    'forums': forums,
    'defaultForumOrder': defaultForumOrder,
    if (userAgent.isNotEmpty) 'userAgent': userAgent,
    if (avatarTemplate != null && avatarTemplate!.isNotEmpty)
      'avatarTemplate': avatarTemplate,
  };

  factory Site.fromJson(Map<String, dynamic> json) => Site(
    name: json['name']?.toString() ?? '',
    baseUrl: json['baseUrl']?.toString() ?? '',
    loginPagePath:
        json['loginPagePath']?.toString() ??
        '/member.php?mod=logging&action=login',
    forums: Map<String, String>.from(json['forums'] as Map? ?? {}),
    defaultForumOrder: List<String>.from(
      json['defaultForumOrder'] as List? ?? [],
    ),
    userAgent: json['userAgent']?.toString() ?? '',
    avatarTemplate: json['avatarTemplate']?.toString(),
  );

  static const String uaAndroid =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  static const String uaPc =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
}
