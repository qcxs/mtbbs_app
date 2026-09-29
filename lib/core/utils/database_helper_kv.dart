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

  // =================== 积分公式（按站点） ===================

  Future<String?> getCreditFormula(String host) async {
    final db = await database;
    final record = await _creditFormulaStore.record(host).get(db);
    return record?['value'] as String?;
  }

  Future<void> setCreditFormula(String host, String formula) async {
    final db = await database;
    await _creditFormulaStore.record(host).put(db, {'value': formula});
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

  // =================== 快捷链接（按站点） ===================

  Future<String?> getShortcutLinksRaw(String host) async {
    final db = await database;
    final record = await _shortcutLinksStore.record(host).get(db);
    return record?['value'] as String?;
  }

  Future<void> setShortcutLinksRaw(String host, String json) async {
    final db = await database;
    await _shortcutLinksStore.record(host).put(db, {'value': json});
  }

  // =================== 工具栏配置 ===================

  Future<String?> getToolbarItemsRaw() async {
    final db = await database;
    final record = await _toolbarItemsStore.record('items').get(db);
    return record?['value'] as String?;
  }

  Future<void> setToolbarItemsRaw(String json) async {
    final db = await database;
    await _toolbarItemsStore.record('items').put(db, {'value': json});
  }

  // =================== 快捷键映射 ===================

  Future<String?> getShortcutsRaw() async {
    final db = await database;
    final record = await _shortcutsStore.record('shortcuts').get(db);
    return record?['value'] as String?;
  }

  Future<void> setShortcutsRaw(String json) async {
    final db = await database;
    await _shortcutsStore.record('shortcuts').put(db, {'value': json});
  }

  // =================== 工具栏快捷键 ===================

  Future<String?> getToolbarShortcutsRaw() async {
    final db = await database;
    final record = await _toolbarShortcutsStore.record('tb_shortcuts').get(db);
    return record?['value'] as String?;
  }

  Future<void> setToolbarShortcutsRaw(String json) async {
    final db = await database;
    await _toolbarShortcutsStore.record('tb_shortcuts').put(db, {
      'value': json,
    });
  }

  // =================== 禁用的 BBCode 标签 ===================

  Future<String?> getDisabledBbcodeRaw() async {
    final db = await database;
    final record = await _disabledBbcodeStore.record('disabled').get(db);
    return record?['value'] as String?;
  }

  Future<void> setDisabledBbcodeRaw(String json) async {
    final db = await database;
    await _disabledBbcodeStore.record('disabled').put(db, {'value': json});
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

  Future<void> deleteMeta(String key) async {
    final db = await database;
    await _settingsStore.record(key).delete(db);
  }
}
