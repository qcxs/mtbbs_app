import 'package:mtbbs/core/app/default_config.dart';

/// 站点正文字数上限的默认值（Discuz 默认 65535）。编辑器 / 留言板共用；
/// 用户未在设置中配置时一律按此值计。
const int kDefaultPostMaxLength = 65535;

/// 站点配置 — 数据模型 + 默认值委托
class SiteConfig {
  SiteConfig._();

  static const String cookieDir = 'cookies';

  /// 默认站点列表（首次运行或重置时使用）
  /// 优先从 [DefaultConfig] 加载，失败时回退到内嵌硬编码。
  static List<Site> defaultSites() => DefaultConfig.instance.defaultSites;

  /// 是否为内置默认站点（MT论坛 / 吾爱破解等）。
  ///
  /// 内置站点是 App 的默认配置：不允许删除，也不允许编辑；需要恢复默认值
  /// 时走「重置站点配置」（[SettingsProvider.restoreDefaultSites]）。
  static bool isDefaultSite(Site site) => defaultSites().any(
    (d) => d.baseUrl == site.baseUrl || d.host == site.host,
  );
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

  /// 站点请求参数编码，默认 `utf-8`。
  ///
  /// Discuz 按站点字符集解码 GET 参数：GBK 站点（如 52pojie）如果收到 UTF-8
  /// 字节的中文关键词，会读成乱码、搜索必然无结果。见 `docs/18`。
  final String charset;

  const Site({
    required this.name,
    required this.baseUrl,
    required this.loginPagePath,
    required this.forums,
    required this.defaultForumOrder,
    this.userAgent = '',
    this.avatarTemplate,
    this.charset = 'utf-8',
  });

  String get host => Uri.parse(baseUrl).host;

  /// 当前站点的有效 User-Agent
  String get effectiveUserAgent => userAgent.isNotEmpty ? userAgent : uaAndroid;

  /// 是否使用移动端 UA（含 "Mobile" 关键字）
  bool get isMobileUA => effectiveUserAgent.contains('Mobile');

  /// 站点实际使用的请求编码（空 / 未配置 → `utf-8`）
  String get effectiveCharset {
    final c = charset.trim().toLowerCase();
    return c.isEmpty ? 'utf-8' : c;
  }

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
    String? charset,
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
    charset: charset ?? this.charset,
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
    if (effectiveCharset != 'utf-8') 'charset': effectiveCharset,
  };

  /// 旧版持久化数据没有 `charset` 字段：按 host 兜底，避免升级后 52pojie
  /// 仍然用 UTF-8 发搜索词。
  static String _legacyCharsetFor(String baseUrl) {
    final host = Uri.tryParse(baseUrl)?.host.toLowerCase() ?? '';
    if (host == '52pojie.cn' || host.endsWith('.52pojie.cn')) return 'gbk';
    return 'utf-8';
  }

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
    charset:
        json['charset']?.toString() ??
        _legacyCharsetFor(json['baseUrl']?.toString() ?? ''),
  );

  static const String uaAndroid =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  static const String uaPc =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
}
