import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/config/toolbar_config.dart';
import 'package:mtbbs/core/utils/shortcut_helper.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/api/home/credit/export.dart' as credit_api;
import 'package:mtbbs/api/home/space/export.dart' as space_api;
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/models/managed_item.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/app/avatar_url.dart';
import 'package:mtbbs/core/app/app_page_gate.dart';
import 'package:mtbbs/core/app/default_config.dart';
import 'package:mtbbs/core/parser/bbcode2html.dart';
import 'package:mtbbs/core/utils/database_helper.dart';

part 'settings_provider_defaults.dart';
part 'settings_provider_accessors.dart';
part 'settings_provider_content.dart';
part 'settings_provider_managed_lists.dart';
part 'settings_provider_sites.dart';
part 'settings_provider_persistence.dart';

/// 设置管理 — 统一通过 [DatabaseHelper] 持久化
class SettingsProvider extends ChangeNotifier {
  double _fontSize = 16;
  String _creditFormula = defaultFormula;
  List<ManagedItem> _guideTabs = defaultGuideTabs();

  /// 首页区块（顺序 + 显隐 + 默认展开），见 [defaultHomeSections]
  List<ManagedItem> _homeSections = defaultHomeSections();
  int _currentSiteIndex = 0;

  /// 默认启动 Tab (0=首页, 1=导读, 2=社区, 3=我的)
  int _defaultTabIndex = 0;

  /// 自定义快捷键（key = 动作ID, value = 按键字符串, 如 "Ctrl+T"）
  Map<String, String> _shortcuts = Map.from(ShortcutHelper.defaults);

  /// 全局禁用的 BBCode 样式标签
  Set<String> _disabledBbcodeTags = <String>{};

  /// 自动识别并链接 URL
  bool _autoDetectUrls = true;

  /// 请求携带 Referer / Accept 等浏览器仿真头（模拟浏览器访问）
  bool _simulateBrowserHeaders = true;

  /// 站点返回"非论坛页"（人机验证 / 防火墙）时，自动弹浏览器让用户通过验证
  bool _interstitialAutoVerify = true;

  /// 关闭 App 接管、改用内置浏览器打开的页面 id（空 = 全部走 App 页）
  Set<String> _browserFallbackPages = <String>{};

  /// 终极降级：App 整体退化为内置浏览器（逃生阀）
  bool _browserOnlyMode = false;

  /// 个人空间页数据源覆盖（'' = 跟随「浏览模式」；'mobile'/'desktop' = 本页强制）
  String _spaceSource = '';

  /// 通用错峰间隔（毫秒），头像/预览等批量请求逐个放行
  int _staggerInterval = 40;

  /// 头像缓存天数（-1 表示永不过期），默认取自 defaults.json
  int _avatarCacheDays = DefaultConfig.instance.cacheExpireDays.avatar;

  /// 表情缓存天数（-1 表示永不过期）
  int _emojiCacheDays = DefaultConfig.instance.cacheExpireDays.emoji;

  /// 帖子图片缓存天数（-1 表示永不过期）
  int _imageCacheDays = DefaultConfig.instance.cacheExpireDays.image;

  /// 勋章图片缓存天数（-1 表示永不过期）
  int _medalCacheDays = DefaultConfig.instance.cacheExpireDays.medal;

  /// 用户自定义站点列表（持久化）
  List<Site> _sites = [];

  /// 快捷链接（按域名存储, key = host）
  final Map<String, List<ManagedItem>> _shortcutLinks = {};

  /// 工具栏项配置（全局，只排序+显隐）
  List<ManagedItem> _toolbarItems = defaultToolbarItems();

  /// 工具栏快捷键（与 toolbarItems 分离持久化，key = item id）
  Map<String, String> _toolbarShortcuts = defaultToolbarShortcuts();

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

  /// 生成默认导读 Tab 列表（全量含可见性）
  static List<ManagedItem> defaultGuideTabs() => [
    for (final id in _defaultTabIds)
      ManagedItem(id: id, name: tabLabels[id] ?? id),
  ];

  /// 生成默认首页区块列表
  static List<ManagedItem> defaultHomeSections() => [
    for (final d in _homeSectionDefaults)
      ManagedItem(
        id: d['id'] as String,
        name: d['name'] as String,
        visible: d['visible'] as bool,
        data: {'expanded': d['expanded']},
      ),
  ];

  /// 读取区块的展开状态（缺字段视为折叠）
  static bool homeSectionExpanded(ManagedItem item) =>
      item.data?['expanded'] == true;

  static const tabLabels = {
    'newthread': '最新发表',
    'hot': '热门',
    'new': '最新回复',
    'digest': '精华',
    'sofa': '抢沙发',
    'my': '我的帖子',
  };

  // ==================== 数据库快捷引用 ====================

  DatabaseHelper get _db => DatabaseHelper.instance;

  /// 通知监听者（供 part 扩展复用，规避 @protected 限制）
  void _notify() => notifyListeners();

  bool _showAvatars = true;

  /// 头像尺寸策略（固定某一尺寸可提高头像缓存命中率），默认 middle
  AvatarSizeMode _avatarSizeMode = AvatarSizeMode.middle;

  /// 宽屏时帖子图片最大宽度（px），窄屏占满不受此限制；默认 600
  int _maxImageWidth = 600;

  /// 编辑器启动自检（默认开启，关闭后跳过启动报错，无条件进入编辑器）
  bool _editorStartupCheck = true;

  /// 启动时自动检查更新（仅正式版生效，见 UpdateService.isSupported）
  bool _autoCheckUpdate = true;

  /// 用户跳过的新版本 tag（自动检查不再提示；'' = 未跳过）
  String _skippedUpdateVersion = '';

  // ==================== 留在类体内的成员 ====================
  //
  // 部分设置项 model（如 content_settings.dart / shortcut_settings.dart）
  // 通过回调类型间接持有 [SettingsProvider]，其所在库并未直接 import 本文件，
  // part 内的扩展成员对它们不可见，故以下 getter/setter 必须保留在类体中。

  double get fontSize => _fontSize;

  Set<String> get disabledBbcodeTags => Set.unmodifiable(_disabledBbcodeTags);
  bool get autoDetectUrls => _autoDetectUrls;
  int get historyMaxCount => _historyMaxCount;
  bool get editorStartupCheck => _editorStartupCheck;

  /// 个人空间页数据源覆盖（'' = 跟随「浏览模式」）
  String get spaceSource => _spaceSource;

  List<ManagedItem> get toolbarItems => List.unmodifiable(_toolbarItems);

  String shortcut(String action) =>
      _shortcuts[action] ?? ShortcutHelper.defaults[action] ?? '';

  String toolbarShortcut(String id) =>
      _toolbarShortcuts[id] ?? defaultToolbarShortcuts()[id] ?? '';

  Future<void> setShortcut(String action, String keyString) async {
    _shortcuts[action] = keyString;
    await _db.setShortcutsRaw(jsonEncode(_shortcuts));
    notifyListeners();
  }

  Future<void> setAutoDetectUrls(bool enabled) async {
    _autoDetectUrls = enabled;
    await _db.setSettingBool('autoDetectUrls', enabled);
    notifyListeners();
  }

  Future<void> setToolbarShortcut(String id, String keyString) async {
    _toolbarShortcuts[id] = keyString;
    await _db.setToolbarShortcutsRaw(jsonEncode(_toolbarShortcuts));
    notifyListeners();
  }

  Future<void> setEditorStartupCheck(bool value) async {
    _editorStartupCheck = value;
    await _db.setSettingBool('editorStartupCheck', value);
    notifyListeners();
  }

  Future<void> setFontSize(double size) async {
    _fontSize = size.clamp(12, 32);
    await _db.setSettingDouble('fontSize', _fontSize);
    notifyListeners();
  }

  Future<void> setHistoryMaxCount(int count) async {
    _historyMaxCount = count.clamp(10, 1000);
    await _db.setSettingInt('historyMaxCount', _historyMaxCount);
    notifyListeners();
  }
}
