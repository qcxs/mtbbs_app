part of 'database_helper.dart';

/// 原始 JSON 键值类读写：设置项、站点、账号、图床历史、快捷链接等。
///
/// 公开命名扩展：随宿主 library 被 import/export 后进入调用方作用域，
/// 外部可像实例方法一样调用（extension 成员不是类成员，必须依赖此可见性）。
extension DatabaseHelperKv on DatabaseHelper {
  // =================== 通用设置（替代 SharedPreferences） ===================

  /// 读取字符串设置项
  Future<String?> getSetting(String key) async {
    final db = await database;
    final record = await _settingsStore.record(key).get(db);
    return record?['value'] as String?;
  }

  /// 写入字符串设置项
  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await _settingsStore.record(key).put(db, {'value': value});
  }

  /// 读取 int 设置项
  Future<int?> getSettingInt(String key) async {
    final v = await getSetting(key);
    if (v == null || v.isEmpty) return null;
    return int.tryParse(v);
  }

  /// 写入 int 设置项
  Future<void> setSettingInt(String key, int value) async {
    await setSetting(key, value.toString());
  }

  /// 读取 double 设置项
  Future<double?> getSettingDouble(String key) async {
    final v = await getSetting(key);
    if (v == null || v.isEmpty) return null;
    return double.tryParse(v);
  }

  /// 写入 double 设置项
  Future<void> setSettingDouble(String key, double value) async {
    await setSetting(key, value.toString());
  }

  /// 读取 bool 设置项
  Future<bool?> getSettingBool(String key) async {
    final v = await getSetting(key);
    if (v == null) return null;
    if (v == 'true') return true;
    if (v == 'false') return false;
    return null;
  }

  /// 写入 bool 设置项
  Future<void> setSettingBool(String key, bool value) async {
    await setSetting(key, value.toString());
  }

  /// 删除设置项
  Future<void> deleteSetting(String key) async {
    final db = await database;
    await _settingsStore.record(key).delete(db);
  }

  // =================== 分层设置（应用 / 站点 / 账号） ===================

  /// 应用设置文档（key 固定为 `app`）
  Future<String?> getAppSettingsRaw() async {
    final db = await database;
    final record = await _appSettingsDocStore.record('app').get(db);
    return record?['value'] as String?;
  }

  Future<void> setAppSettingsRaw(String json) async {
    final db = await database;
    await _appSettingsDocStore.record('app').put(db, {'value': json});
  }

  /// 站点设置（按 host）
  Future<String?> getSiteSettingsRaw(String host) async {
    final db = await database;
    final record = await _siteSettingsStore.record(host).get(db);
    return record?['value'] as String?;
  }

  Future<void> setSiteSettingsRaw(String host, String json) async {
    final db = await database;
    await _siteSettingsStore.record(host).put(db, {'value': json});
  }

  Future<void> deleteSiteSettings(String host) async {
    final db = await database;
    await _siteSettingsStore.record(host).delete(db);
  }

  /// 账号设置（按 host + uid）
  Future<String?> getAccountSettingsRaw(String host, String uid) async {
    final db = await database;
    final record = await _accountSettingsStore.record('$host|$uid').get(db);
    return record?['value'] as String?;
  }

  Future<void> setAccountSettingsRaw(
    String host,
    String uid,
    String json,
  ) async {
    final db = await database;
    await _accountSettingsStore.record('$host|$uid').put(db, {'value': json});
  }

  /// 站点派生状态（key = `host|kind`）
  Future<String?> getSiteStateRaw(String host, String kind) async {
    final db = await database;
    final record = await _siteStateStore.record('$host|$kind').get(db);
    return record?['value'] as String?;
  }

  Future<void> setSiteStateRaw(String host, String kind, String json) async {
    final db = await database;
    await _siteStateStore.record('$host|$kind').put(db, {'value': json});
  }

  Future<void> deleteSiteState(String host, {String? kind}) async {
    final db = await database;
    if (kind != null) {
      await _siteStateStore.record('$host|$kind').delete(db);
      return;
    }
    final records = await _siteStateStore.find(
      db,
      finder: Finder(
        filter: Filter.matches(Field.key, '^${RegExp.escape(host)}\\|'),
      ),
    );
    for (final record in records) {
      await _siteStateStore.record(record.key).delete(db);
    }
  }

  // =================== 站点列表 ===================

  Future<String?> getSitesRaw() async {
    final db = await database;
    final record = await _sitesStore.record('sites').get(db);
    return record?['value'] as String?;
  }

  Future<void> setSitesRaw(String json) async {
    final db = await database;
    await _sitesStore.record('sites').put(db, {'value': json});
  }

  // =================== 账号列表（按站点隔离） ===================

  Future<String?> getAccountsRaw(String host) async {
    final db = await database;
    final record = await _accountsStore.record(host).get(db);
    return record?['value'] as String?;
  }

  Future<void> setAccountsRaw(String host, String json) async {
    final db = await database;
    await _accountsStore.record(host).put(db, {'value': json});
  }

  Future<void> deleteAccounts(String host) async {
    final db = await database;
    await _accountsStore.record(host).delete(db);
  }

  // =================== 上次登录账号 ===================

  Future<String?> getLastAccount(String host) async {
    final db = await database;
    final record = await _lastAccountStore.record(host).get(db);
    return record?['value'] as String?;
  }

  Future<void> setLastAccount(String host, String username) async {
    final db = await database;
    await _lastAccountStore.record(host).put(db, {'value': username});
  }

  Future<void> deleteLastAccount(String host) async {
    final db = await database;
    await _lastAccountStore.record(host).delete(db);
  }

  // =================== 图床历史 ===================

  Future<String?> getImageHistoryRaw() async {
    final db = await database;
    final record = await _imageHistoryStore.record('history').get(db);
    return record?['value'] as String?;
  }

  Future<void> setImageHistoryRaw(String json) async {
    final db = await database;
    await _imageHistoryStore.record('history').put(db, {'value': json});
  }

  // =================== 元数据存储（通用键值对） ===================

  /// 通用字符串元数据（供临时或非结构化数据使用）
  Future<String?> getMeta(String key) async {
    final db = await database;
    final record = await _settingsStore.record(key).get(db);
    return record?['value'] as String?;
  }

  Future<void> setMeta(String key, String value) async {
    final db = await database;
    await _settingsStore.record(key).put(db, {'value': value});
  }
}
