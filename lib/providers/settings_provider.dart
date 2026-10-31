import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/config/notice_config.dart';
import 'package:mtbbs/config/toolbar_config.dart';
import 'package:mtbbs/core/utils/shortcut_helper.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/api/home/credit/export.dart' as credit_api;
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/services/thread_cache_service.dart';
import 'package:mtbbs/models/managed_item.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/app/session_registry.dart';
import 'package:mtbbs/core/app/avatar_url.dart';
import 'package:mtbbs/core/app/avatar_redirect_store.dart';
import 'package:mtbbs/core/app/default_config.dart';
import 'package:mtbbs/core/app/stagger_queue.dart' as stagger_queue;
import 'package:mtbbs/core/parser/bbcode2html.dart';
import 'package:mtbbs/core/settings/settings_repository.dart';
import 'package:mtbbs/core/utils/cache_utils.dart';
import 'package:mtbbs/core/utils/database_helper.dart';
import 'package:mtbbs/core/utils/frequent_order.dart';
import 'package:mtbbs/models/settings/app_settings.dart';
import 'package:mtbbs/models/settings/settings_defaults.dart'
    as settings_defaults;
import 'package:mtbbs/models/settings/site_settings.dart';

part 'settings_provider_accessors.dart';
part 'settings_provider_content.dart';
part 'settings_provider_managed_lists.dart';
part 'settings_provider_sites.dart';
part 'settings_provider_persistence.dart';

/// 设置管理 — 统一通过 [DatabaseHelper] 持久化
class SettingsProvider extends ChangeNotifier {
  double _fontSize = 16;
  List<ManagedItem> _guideTabs = settings_defaults.defaultGuideTabs();

  /// 首页区块（顺序 + 显隐 + 默认展开）
  List<ManagedItem> _homeSections = settings_defaults.defaultHomeSections();
  int _currentSiteIndex = 0;

  /// 默认启动 Tab (0=首页, 1=导读, 2=社区, 3=我的)
  int _defaultTabIndex = 0;

  /// Android 返回键在默认页的「双击退出」（默认开；关闭后按一次返回即退出）
  bool _doubleBackExit = true;

  /// 自定义快捷键（key = 动作ID, value = 按键字符串, 如 "Ctrl+T"）
  Map<String, String> _shortcuts = Map.from(ShortcutHelper.defaults);

  /// 全局禁用的 BBCode 样式标签
  Set<String> _disabledBbcodeTags = <String>{};

  /// 自动识别并链接 URL
  bool _autoDetectUrls = true;

  /// 代码块折叠态最大行数；0 = 不限制
  int _codeBlockMaxLines = 18;

  /// 楼层内评分区最多显示条数；0 = 不限制
  int _ratingMaxRows = 10;

  /// 消息未读标记样式（隐藏 / 红点 / 数字）
  NoticeBadgeMode _noticeBadgeMode = NoticeBadgeMode.number;

  /// 是否检查新提醒（关掉后完全不请求，见 NoticeBadgeController）
  bool _noticeCheckEnabled = true;

  /// 计入底栏未读的分组 id（默认全部，见 notice_config 的 noticeGroups）
  Set<String> _noticeBadgeGroups = noticeGroupIds;

  /// 消息页 Tab（顺序 + 显隐）
  List<ManagedItem> _noticeTabs = settings_defaults.defaultNoticeTabs();

  /// 「常用项自动前排」：按使用次数把常用的 Tab 排到前面（默认开）
  bool _autoFrequentTabs = true;

  /// Tab 使用次数：scope → id → 次数（scope 见 [kTabUsageGuide] / [kTabUsageNotice]）
  Map<String, Map<String, int>> _tabUsage = {};

  /// 开发者选项是否已解锁（关于页图标连点解锁）。解锁后关于页图标单击即进入
  bool _developerMode = false;

  /// 通用错峰间隔（毫秒），头像/预览等批量请求逐个放行
  int _staggerInterval = 40;

  /// 头像缓存天数（-1 表示永不过期），默认取自 cache.json
  int _avatarCacheDays = DefaultConfig.instance.cacheExpireDays.avatar;

  /// 表情缓存天数（-1 表示永不过期）
  int _emojiCacheDays = DefaultConfig.instance.cacheExpireDays.emoji;

  /// 帖子图片缓存天数（-1 表示永不过期）
  int _imageCacheDays = DefaultConfig.instance.cacheExpireDays.image;

  /// 勋章图片缓存天数（-1 表示永不过期）
  int _medalCacheDays = DefaultConfig.instance.cacheExpireDays.medal;

  /// 帖子自动缓存过期天数（下限 1，不提供「永不过期」）
  int _threadCacheDays = DefaultConfig.instance.threadCacheConfig.expireDays;

  /// 帖子自动缓存总开关（默认开启）。关闭后不再写入新缓存，
  /// 已有缓存仍可查看/管理。
  bool _threadCacheEnabled = true;

  /// 每帖保留的自动缓存正文版本数（默认 3）
  int _threadCacheMaxVersions = ThreadCacheService.defaultMaxVersions;

  /// 单帖最大缓存大小（KB，默认取自 cache.json，当前 128 KB）
  int _threadCacheMaxKB =
      DefaultConfig.instance.threadCacheConfig.maxBytesPerThread ~/ 1024;

  /// 用户自定义站点列表（持久化）
  List<Site> _sites = [];

  /// 工具栏项配置（全局，只排序+显隐）
  List<ManagedItem> _toolbarItems = defaultToolbarItems();

  /// 工具栏快捷键（与 toolbarItems 分离持久化，key = item id）
  Map<String, String> _toolbarShortcuts = defaultToolbarShortcuts();

  /// 帖子页是否使用内嵌迷你编辑器（关闭则退回原全屏编辑器）
  bool _threadMiniEditor = true;

  /// 帖子迷你编辑器「常用语」（可增删排序；内容限 100 字）
  List<ManagedItem> _quickReplies = settings_defaults.defaultQuickReplies();

  // ==================== 编辑器配置 ====================

  /// 快照最短字数（低于此不保存）
  int _minSnapshotWordCount = 10;

  /// 自动保存间隔（秒）
  int _autoSaveInterval = 30;

  /// 每会话自动快照上限
  int _maxAutoSnapshots = 10;

  // ==================== 浏览历史配置 ====================

  /// 帖子插入格式（占位符如 {title}、{author}、{time}）
  String _historyFormatThread = '{title}';

  /// 用户插入格式（占位符如 {nickname}、{uid}）
  String _historyFormatUser = '{nickname}';

  /// 最大记录数
  int _historyMaxCount = 200;

  /// 历史记录标题格式 — 帖子
  String _historyTitleFormatThread = '{title} by:{author} {time}';

  /// 历史记录标题格式 — 用户
  String _historyTitleFormatUser = '{nickname}(UID={uid})';

  /// 历史记录标题格式 — 我的帖子
  String _historyTitleFormatMythread = '{typeLabel}(UID={uid}, 第{page}页)';

  /// 历史记录标题格式 — 回复
  String _historyTitleFormatReply = '{typeLabel}(UID={uid}, 第{page}页)';

  /// 主题模式
  ThemeMode _themeMode = ThemeMode.system;

  /// 主题种子色
  Color _seedColor = const Color(0xFF9E9E9E);

  /// 纯黑主题（仅深色模式下生效）
  bool _isPureBlackTheme = false;

  /// 预设主题色
  static const Map<String, Color> presetColors = {
    '纯白': Color(0xFF9E9E9E),
    '深紫': Colors.deepPurple,
    '亮蓝': Colors.blue,
    '青色': Colors.teal,
    '翠绿': Colors.green,
    '珊瑚': Color(0xFFFF6B6B),
  };

  static const String defaultFormula = '';

  static List<ManagedItem> defaultHomeSections() =>
      settings_defaults.defaultHomeSections();

  /// 读取区块的展开状态（缺字段视为折叠）
  static bool homeSectionExpanded(ManagedItem item) =>
      item.data?['expanded'] == true;

  static const tabLabels = settings_defaults.kSettingsTabLabels;

  // ==================== 数据库快捷引用 ====================

  DatabaseHelper get _db => DatabaseHelper.instance;

  /// 分层设置的唯一读写入口
  SettingsRepository get _settings => SettingsRepository.instance;

  /// 通知监听者（供 part 扩展复用，规避 @protected 限制）
  void _notify() => notifyListeners();

  bool _showAvatars = true;

  /// 头像尺寸策略（固定某一尺寸可提高头像缓存命中率），默认 middle
  AvatarSizeMode _avatarSizeMode = AvatarSizeMode.middle;

  /// 宽屏时帖子图片最大宽度（px），窄屏占满不受此限制；默认 600
  int _maxImageWidth = 600;

  /// 分享图正文最大高度（逻辑像素）：生成页勾选「截断」时生效
  int _shareImageMaxHeight = 8000;

  /// 「生成图片」只输出正文（不含作者信息 / 评分、页脚与定位信息），默认关
  bool _shareImageContentOnly = false;

  /// 编辑器启动自检（默认开启，关闭后跳过启动报错，无条件进入编辑器）
  bool _editorStartupCheck = true;

  /// 工具栏项被隐藏时，其快捷键是否仍然生效（默认开启）
  bool _toolbarShortcutWhenHidden = true;

  /// 启动时自动检查更新（需构建注入更新源，且受 1 小时限流，见 UpdateService）
  bool _autoCheckUpdate = true;

  /// 用户跳过的新版本 tag（自动检查不再提示；'' = 未跳过）
  String _skippedUpdateVersion = '';

  /// 上次检查更新的时间（Unix 秒，0 = 从未检查）；自动检查 1 小时内不重复
  int _lastUpdateCheckAt = 0;

  // ==================== 留在类体内的成员 ====================
  //
  // 部分设置项 model（如 content_settings.dart / shortcut_settings.dart）
  // 通过回调类型间接持有 [SettingsProvider]，其所在库并未直接 import 本文件，
  // part 内的扩展成员对它们不可见，故以下 getter/setter 必须保留在类体中。

  double get fontSize => _fontSize;

  /// 代码块折叠态最大行数；0 = 不限制
  int get codeBlockMaxLines => _codeBlockMaxLines;

  /// 楼层内评分区最多显示条数；0 = 不限制
  int get ratingMaxRows => _ratingMaxRows;

  Set<String> get disabledBbcodeTags => Set.unmodifiable(_disabledBbcodeTags);
  bool get autoDetectUrls => _autoDetectUrls;
  int get historyMaxCount => _historyMaxCount;
  bool get editorStartupCheck => _editorStartupCheck;

  List<ManagedItem> get toolbarItems => List.unmodifiable(_toolbarItems);

  String shortcut(String action) =>
      _shortcuts[action] ?? ShortcutHelper.defaults[action] ?? '';

  String toolbarShortcut(String id) =>
      _toolbarShortcuts[id] ?? defaultToolbarShortcuts()[id] ?? '';

  Future<void> setShortcut(String action, String keyString) async {
    _shortcuts[action] = keyString;
    await _persistApp();
    notifyListeners();
  }

  Future<void> setAutoDetectUrls(bool enabled) async {
    _autoDetectUrls = enabled;
    await _persistApp();
    notifyListeners();
  }

  Future<void> setToolbarShortcut(String id, String keyString) async {
    _toolbarShortcuts[id] = keyString;
    await _persistApp();
    notifyListeners();
  }

  Future<void> setEditorStartupCheck(bool value) async {
    _editorStartupCheck = value;
    await _persistApp();
    notifyListeners();
  }

  /// 开关"工具栏项被隐藏时其快捷键仍然生效"
  Future<void> setToolbarShortcutWhenHidden(bool value) async {
    _toolbarShortcutWhenHidden = value;
    await _persistApp();
    notifyListeners();
  }

  Future<void> setFontSize(double size) async {
    _fontSize = size.clamp(12, 32);
    await _persistApp();
    notifyListeners();
  }

  Future<void> setHistoryMaxCount(int count) async {
    _historyMaxCount = count.clamp(10, 1000);
    await _persistApp();
    notifyListeners();
  }
}
