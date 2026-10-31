part of 'database_helper.dart';

// =================== Store 定义 ===================
//
// 原为 DatabaseHelper 的 static final 字段；static 成员不能搬进 extension，
// 故移到顶层私有 final（顶层私有符号在整个 library 可见，宿主类体内与各
// extension 内均可无前缀引用）。这些字段仅本文件使用，无外部引用。

/// 浏览记录 — String key（record.id），Map value
final _browseStore = stringMapStoreFactory.store('browse_records');

/// 搜索历史 — int auto-increment key，Map value
final _searchStore = intMapStoreFactory.store('search_history');

/// 编辑器快照 — String key（snapshot.id），Map value
final _snapshotStore = stringMapStoreFactory.store('editor_snapshots');

/// 帖子预览缓存 — String key（tid_pid），Map value
final _previewStore = stringMapStoreFactory.store('preview_cache');

/// 设置项 — String key → {value: String}，替代 SharedPreferences
///
/// 旧扁平设置仍保留此 Store；新分层设置使用下面三个 Store。
final _settingsStore = stringMapStoreFactory.store('app_settings');

/// 应用设置文档 — 固定 key "app" → AppSettings JSON
final _appSettingsDocStore = stringMapStoreFactory.store('settings_app');

/// 站点设置 — String key (host) → SiteSettings JSON
final _siteSettingsStore = stringMapStoreFactory.store('settings_site');

/// 账号设置 — String key (host|uid) → AccountSettings JSON
final _accountSettingsStore = stringMapStoreFactory.store('settings_account');

/// 站点派生状态 — String key (host|kind) → JSON（表情、作者资料等）
final _siteStateStore = stringMapStoreFactory.store('site_state');

/// 账号列表 — String key (host) → JSON: List<Account>
final _accountsStore = stringMapStoreFactory.store('app_accounts');

/// 图床历史 — 固定 key "history" → JSON: List<MtUploadResult>
final _imageHistoryStore = stringMapStoreFactory.store('image_history');

/// 站点列表 — 固定 key "sites" → JSON: List<Site>
final _sitesStore = stringMapStoreFactory.store('app_sites');

/// 上次登录账号 — String key (host) → {value: String}
final _lastAccountStore = stringMapStoreFactory.store('last_account');

/// 头像重定向映射 — 每条映射一条记录：key=原始URL → {final: 最终URL|null, updatedAt: ms}
final _avatarRedirectStore = stringMapStoreFactory.store('avatar_redirects');
