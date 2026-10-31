import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/core/app/default_config.dart';
import 'package:mtbbs/models/managed_item.dart';

/// 站点设置（与账号无关，按 host 隔离）
class SiteSettings {
  final int schemaVersion;
  final String host;
  final SiteNetworkSettings network;
  final SitePageGateSettings pages;
  final SiteContentSettings content;
  final SiteIdentitySettings identity;
  final String creditFormula;
  final List<ManagedItem> shortcutLinks;
  final SiteCdnRecord? cdn;

  const SiteSettings({
    this.schemaVersion = 1,
    required this.host,
    required this.network,
    required this.pages,
    required this.content,
    required this.identity,
    this.creditFormula = '',
    this.shortcutLinks = const [],
    this.cdn,
  });

  factory SiteSettings.defaults(String host) => SiteSettings(
    host: host,
    network: SiteNetworkSettings.defaults(),
    pages: SitePageGateSettings.defaults(),
    content: SiteContentSettings.defaults(),
    identity: SiteIdentitySettings.defaults(),
    shortcutLinks: DefaultConfig.instance.shortcutLinksFor(host),
  );

  SiteSettings copyWith({
    SiteNetworkSettings? network,
    SitePageGateSettings? pages,
    SiteContentSettings? content,
    SiteIdentitySettings? identity,
    String? creditFormula,
    List<ManagedItem>? shortcutLinks,
    SiteCdnRecord? cdn,
    bool clearCdn = false,
  }) => SiteSettings(
    schemaVersion: schemaVersion,
    host: host,
    network: network ?? this.network,
    pages: pages ?? this.pages,
    content: content ?? this.content,
    identity: identity ?? this.identity,
    creditFormula: creditFormula ?? this.creditFormula,
    shortcutLinks: shortcutLinks ?? this.shortcutLinks,
    cdn: clearCdn ? null : (cdn ?? this.cdn),
  );

  Map<String, dynamic> toMap() => {
    'schemaVersion': schemaVersion,
    'host': host,
    'network': network.toMap(),
    'pages': pages.toMap(),
    'content': content.toMap(),
    'identity': identity.toMap(),
    'creditFormula': creditFormula,
    'shortcutLinks': shortcutLinks.map((e) => e.toJson()).toList(),
    'cdn': cdn?.toMap(),
  };

  factory SiteSettings.fromMap(String host, Map<String, dynamic> map) {
    Map<String, dynamic> sub(String key) =>
        (map[key] as Map?)?.cast<String, dynamic>() ?? const {};
    final d = SiteSettings.defaults(host);
    final links = map['shortcutLinks'];
    final cdnMap = (map['cdn'] as Map?)?.cast<String, dynamic>();
    return SiteSettings(
      schemaVersion: (map['schemaVersion'] as num?)?.toInt() ?? 1,
      host: host,
      network: SiteNetworkSettings.fromMap(sub('network')),
      pages: SitePageGateSettings.fromMap(sub('pages')),
      content: SiteContentSettings.fromMap(sub('content')),
      identity: SiteIdentitySettings.fromMap(sub('identity')),
      creditFormula: map['creditFormula']?.toString() ?? d.creditFormula,
      shortcutLinks: links is List
          ? links
                .whereType<Map>()
                .map((e) => ManagedItem.fromJson(e.cast<String, dynamic>()))
                .where((e) => e.id.isNotEmpty)
                .toList()
          : d.shortcutLinks,
      cdn: cdnMap == null ? null : SiteCdnRecord.fromMap(cdnMap),
    );
  }
}

class SiteNetworkSettings {
  /// API 与图片请求是否携带 Referer / Accept
  final bool simulateBrowserHeaders;

  /// 站点返回验证/防火墙页时是否自动弹浏览器
  final bool interstitialAutoVerify;

  /// 跳过本地自解，强制用 WebView 完成人机验证
  final bool acwForceWebview;

  const SiteNetworkSettings({
    required this.simulateBrowserHeaders,
    required this.interstitialAutoVerify,
    required this.acwForceWebview,
  });

  factory SiteNetworkSettings.defaults() => const SiteNetworkSettings(
    simulateBrowserHeaders: true,
    interstitialAutoVerify: true,
    acwForceWebview: false,
  );

  SiteNetworkSettings copyWith({
    bool? simulateBrowserHeaders,
    bool? interstitialAutoVerify,
    bool? acwForceWebview,
  }) => SiteNetworkSettings(
    simulateBrowserHeaders:
        simulateBrowserHeaders ?? this.simulateBrowserHeaders,
    interstitialAutoVerify:
        interstitialAutoVerify ?? this.interstitialAutoVerify,
    acwForceWebview: acwForceWebview ?? this.acwForceWebview,
  );

  Map<String, dynamic> toMap() => {
    'simulateBrowserHeaders': simulateBrowserHeaders,
    'interstitialAutoVerify': interstitialAutoVerify,
    'acwForceWebview': acwForceWebview,
  };

  factory SiteNetworkSettings.fromMap(Map<String, dynamic> map) {
    final d = SiteNetworkSettings.defaults();
    return SiteNetworkSettings(
      simulateBrowserHeaders:
          map['simulateBrowserHeaders'] as bool? ?? d.simulateBrowserHeaders,
      interstitialAutoVerify:
          map['interstitialAutoVerify'] as bool? ?? d.interstitialAutoVerify,
      acwForceWebview: map['acwForceWebview'] as bool? ?? d.acwForceWebview,
    );
  }
}

class SitePageGateSettings {
  /// 已关闭 App 接管的页面 id（空 = 全部走 App 页）
  final Set<String> disabledPageIds;

  /// 本站点整体退化为内置浏览器
  final bool browserOnly;

  const SitePageGateSettings({
    required this.disabledPageIds,
    required this.browserOnly,
  });

  factory SitePageGateSettings.defaults() =>
      const SitePageGateSettings(disabledPageIds: {}, browserOnly: false);

  SitePageGateSettings copyWith({
    Set<String>? disabledPageIds,
    bool? browserOnly,
  }) => SitePageGateSettings(
    disabledPageIds: disabledPageIds ?? this.disabledPageIds,
    browserOnly: browserOnly ?? this.browserOnly,
  );

  Map<String, dynamic> toMap() => {
    'disabledPageIds': disabledPageIds.toList(),
    'browserOnly': browserOnly,
  };

  factory SitePageGateSettings.fromMap(Map<String, dynamic> map) {
    final d = SitePageGateSettings.defaults();
    final ids = map['disabledPageIds'];
    return SitePageGateSettings(
      disabledPageIds: ids is List
          ? ids.map((e) => e.toString()).toSet()
          : d.disabledPageIds,
      browserOnly: map['browserOnly'] as bool? ?? d.browserOnly,
    );
  }
}

class SiteContentSettings {
  /// 站点允许的单帖 / 留言最大字数
  final int postMaxLength;

  /// 个人空间页数据源：'' 跟随浏览模式 / mobile / desktop
  final String spaceSource;

  const SiteContentSettings({
    required this.postMaxLength,
    required this.spaceSource,
  });

  factory SiteContentSettings.defaults() => const SiteContentSettings(
    postMaxLength: kDefaultPostMaxLength,
    spaceSource: '',
  );

  SiteContentSettings copyWith({int? postMaxLength, String? spaceSource}) =>
      SiteContentSettings(
        postMaxLength: postMaxLength ?? this.postMaxLength,
        spaceSource: spaceSource ?? this.spaceSource,
      );

  Map<String, dynamic> toMap() => {
    'postMaxLength': postMaxLength,
    'spaceSource': spaceSource,
  };

  factory SiteContentSettings.fromMap(Map<String, dynamic> map) {
    final d = SiteContentSettings.defaults();
    return SiteContentSettings(
      postMaxLength: (map['postMaxLength'] as num?)?.toInt() ?? d.postMaxLength,
      spaceSource: map['spaceSource']?.toString() ?? d.spaceSource,
    );
  }
}

class SiteIdentitySettings {
  /// 该站点的默认用户；null / 空串 = 游客
  final String? defaultAccount;

  const SiteIdentitySettings({this.defaultAccount});

  factory SiteIdentitySettings.defaults() => const SiteIdentitySettings();

  SiteIdentitySettings copyWith({String? defaultAccount, bool clear = false}) =>
      SiteIdentitySettings(
        defaultAccount: clear ? null : (defaultAccount ?? this.defaultAccount),
      );

  Map<String, dynamic> toMap() => {'defaultAccount': defaultAccount};

  factory SiteIdentitySettings.fromMap(Map<String, dynamic> map) {
    final v = map['defaultAccount']?.toString() ?? '';
    return SiteIdentitySettings(defaultAccount: v.isEmpty ? null : v);
  }
}

class SiteCdnRecord {
  final String value;
  final int checkedAtMs;

  const SiteCdnRecord({required this.value, required this.checkedAtMs});

  Map<String, dynamic> toMap() => {'value': value, 'checkedAtMs': checkedAtMs};

  factory SiteCdnRecord.fromMap(Map<String, dynamic> map) => SiteCdnRecord(
    value: map['value']?.toString() ?? '',
    checkedAtMs: (map['checkedAtMs'] as num?)?.toInt() ?? 0,
  );
}
