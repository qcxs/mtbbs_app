import 'package:dio/dio.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/services/api_service.dart';

/// 主会话（全局当前站点 + 当前账号）的身份快照。
///
/// 由 [SessionRegistry.bindIdentity] 在启动时绑定到 `AuthProvider`，
/// 避免 core 层反向依赖 auth 层。
class SiteIdentity {
  final String uid;
  final String username;
  final bool isLoggedIn;

  const SiteIdentity({
    this.uid = '0',
    this.username = '',
    this.isLoggedIn = false,
  });

  static const guest = SiteIdentity();
}

/// 一次页面访问所用的「站点 + 身份」上下文。
///
/// - 主会话（[GlobalSiteSession]）：跟随 SiteStore / AuthProvider，行为与旧版一致；
/// - 跨站点会话（[FixedSiteSession]）：临时生效另一个站点 + 该站默认账号（缺省游客），
///   并把 Dio 绑到该站点的 Cookie 罐，从而不再需要"切换站点"。
///
/// 页面通过 `SiteScope.of(context)` 拿到会话，用 [dio] / [host] / [baseUrl]
/// 代替全局单例读取 —— 这就是"API 无状态"的落点。
abstract class SiteSession {
  /// 站点域名
  String get host;

  /// 站点 baseUrl（不带末尾 `/`）
  String get baseUrl;

  /// 生效账号名，null = 游客
  String? get accountName;

  String get uid;

  String get username;

  bool get isLoggedIn;

  /// 是否为跨站点临时会话
  bool get temporary;

  /// 绑定到本会话站点 + 账号的 Dio
  Dio get dio;

  /// 是否允许写操作（发帖 / 评论 / 点赞等）。
  ///
  /// 跨站点会话一律只读：默认账号只是"用来读"的身份，写入仍要求用户主动切站点，
  /// 否则会出现"以为在 A 站发帖、实际发到 B 站"这类危险歧义。
  bool get canWrite => isLoggedIn && !temporary;
}

/// 主会话：跟随全局当前站点与当前账号（零迁移路径）
class GlobalSiteSession implements SiteSession {
  const GlobalSiteSession();

  @override
  String get host => SiteStore.instance.host;

  @override
  String get baseUrl => SiteStore.instance.baseUrl;

  @override
  String? get accountName => isLoggedIn ? username : null;

  @override
  String get uid => SessionRegistryIdentity.current.uid;

  @override
  String get username => SessionRegistryIdentity.current.username;

  @override
  bool get isLoggedIn => SessionRegistryIdentity.current.isLoggedIn;

  @override
  bool get temporary => false;

  @override
  bool get canWrite => isLoggedIn && !temporary;

  @override
  Dio get dio => ApiService().dio;
}

/// 跨站点临时会话：固定站点 + 固定账号（null = 游客）
class FixedSiteSession implements SiteSession {
  @override
  final String host;

  @override
  final String baseUrl;

  @override
  final String? accountName;

  @override
  final String uid;

  @override
  final String username;

  @override
  final Dio dio;

  FixedSiteSession({
    required this.host,
    required this.baseUrl,
    required this.accountName,
    required this.uid,
    required this.username,
    required this.dio,
  });

  @override
  bool get isLoggedIn => uid.isNotEmpty && uid != '0';

  @override
  bool get temporary => true;

  @override
  bool get canWrite => isLoggedIn && !temporary;
}

/// 身份读取的轻量间接层（由 [SessionRegistry] 在启动时绑定 AuthProvider）
class SessionRegistryIdentity {
  SessionRegistryIdentity._();

  static SiteIdentity Function() _reader = () => SiteIdentity.guest;

  static SiteIdentity get current {
    try {
      return _reader();
    } catch (_) {
      return SiteIdentity.guest;
    }
  }

  static void bind(SiteIdentity Function() reader) {
    _reader = reader;
  }
}
