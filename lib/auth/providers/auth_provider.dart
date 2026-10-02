import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/app/cookie_sync.dart';
import 'package:mtbbs/core/utils/database_helper.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/api/misc/userstatus/export.dart' as userstatus_api;

part 'auth_provider_account.dart';
part 'auth_provider_accounts.dart';
part 'auth_provider_site.dart';

/// 登录状态管理 — 按站点隔离
///
/// 每个站点的账号列表独立存储、独立活跃索引。
/// 切换站点时自动切换账号上下文。
class AuthProvider extends ChangeNotifier {
  /// 按站点 host 分组的账号列表
  final Map<String, List<Account>> _siteAccounts = {};

  /// 按站点 host 记录的活跃索引
  final Map<String, int> _siteActiveIndex = {};

  bool _guestInitialized = false;

  // ==================== 当前站点快捷访问 ====================

  String get _host => SiteStore.instance.host;

  List<Account> get _currentAccounts =>
      _siteAccounts.putIfAbsent(_host, () => []);

  int get _currentActiveIndex {
    _siteActiveIndex.putIfAbsent(_host, () => -1);
    return _siteActiveIndex[_host]!;
  }

  set _currentActiveIndex(int v) => _siteActiveIndex[_host] = v;

  /// 通知监听者（供 part 扩展复用，规避 @protected 限制）
  void _notify() => notifyListeners();
}
