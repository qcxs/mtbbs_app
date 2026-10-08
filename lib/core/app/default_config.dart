import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/models/managed_item.dart';

/// 默认配置加载器 — 从 `assets/config/` 下**按域拆分**的 JSON 加载默认值
///
/// | 文件 | 域 | 顶层键 |
/// |---|---|---|
/// | `sites.json` | 站点与快捷链接（关键） | `sites` / `shortcutLinks` |
/// | `toolbar.json` | 编辑器工具栏项（含默认快捷键/模板） | `items` |
/// | `shortcuts.json` | 全局快捷键 | `global` |
/// | `cache.json` | 图片缓存过期天数 | `expireDays` |
///
/// 各文件**独立容错**：加载失败或 JSON 错误只让对应域返回空/默认，不影响其它域。
/// 只有站点配置带硬编码回退（否则 App 无法启动）。
class DefaultConfig {
  DefaultConfig._();
  static final DefaultConfig instance = DefaultConfig._();

  Map<String, dynamic>? _sites;
  Map<String, dynamic>? _toolbar;
  Map<String, dynamic>? _shortcuts;
  Map<String, dynamic>? _cache;

  /// 从 assets 加载全部默认配置（每个文件独立 try/catch）
  Future<void> load() async {
    _sites = await _loadJson('assets/config/sites.json');
    _toolbar = await _loadJson('assets/config/toolbar.json');
    _shortcuts = await _loadJson('assets/config/shortcuts.json');
    _cache = await _loadJson('assets/config/cache.json');
  }

  Future<Map<String, dynamic>?> _loadJson(String path) async {
    try {
      final raw = await rootBundle.loadString(path);
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ==================== 站点（关键，异常有回退） ====================

  /// 默认站点列表
  List<Site> get defaultSites {
    final list = _sites?['sites'] as List<dynamic>?;
    if (list != null && list.isNotEmpty) {
      return list.map((j) => Site.fromJson(j as Map<String, dynamic>)).toList();
    }
    return [
      Site(
        name: 'MT论坛',
        baseUrl: 'https://bbs.binmt.cc',
        loginPagePath: '/member.php?mod=logging&action=login',
        forums: {},
        defaultForumOrder: [],
      ),
      Site(
        name: '吾爱破解',
        baseUrl: 'https://www.52pojie.cn',
        loginPagePath: '/member.php?mod=logging&action=login',
        forums: {},
        defaultForumOrder: [],
        avatarTemplate:
            'https://avatar.52pojie.cn/data/avatar/{dir}/{tail}_avatar_{size}.jpg',
      ),
    ];
  }

  // ==================== 快捷链接（非关键，JSON 失败返回空） ====================

  /// 返回指定站点的默认快捷链接
  List<ManagedItem> shortcutLinksFor(String host) {
    final perSite = _sites?['shortcutLinks'] as Map<String, dynamic>?;
    if (perSite == null) return [];
    final links = perSite[host] as List<dynamic>?;
    if (links == null) return [];
    return links.map((j) {
      final m = j as Map<String, dynamic>;
      return ManagedItem(
        id: m['id']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        data: {'url': m['url']?.toString() ?? ''},
      );
    }).toList();
  }

  // ==================== 工具栏（非关键，JSON 失败返回空） ====================

  /// 工具栏项配置列表，JSON 失败时返回空
  List<Map<String, dynamic>> get toolbarConfigs {
    final list = _toolbar?['items'] as List<dynamic>?;
    if (list == null) return [];
    return list.cast<Map<String, dynamic>>();
  }

  /// 生成默认的工具栏项列表（按 JSON 顺序），JSON 失败返回空
  ///
  /// `template` / `label` / `group` / `block` 原样收进 [ManagedItem.data]，
  /// 供工具栏渲染与「模板应用」读取（见 `config/toolbar_config.dart`）。
  List<ManagedItem> get defaultToolbarItems {
    final configs = toolbarConfigs;
    if (configs.isEmpty) return [];
    return configs.map((m) {
      final data = <String, dynamic>{};
      final template = m['template']?.toString();
      if (template != null && template.isNotEmpty) {
        data['template'] = template;
      }
      final label = m['label']?.toString();
      if (label != null && label.isNotEmpty) data['label'] = label;
      final group = m['group']?.toString();
      if (group != null && group.isNotEmpty) data['group'] = group;
      if (m['block'] == true) data['block'] = true;
      return ManagedItem(
        id: m['id']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        visible: (m['visible'] as bool?) ?? true,
        data: data.isEmpty ? null : data,
      );
    }).toList();
  }

  /// 生成默认的工具栏快捷键映射，JSON 失败返回空
  Map<String, String> get defaultToolbarShortcuts {
    final configs = toolbarConfigs;
    if (configs.isEmpty) return const {};
    final result = <String, String>{};
    for (final m in configs) {
      final shortcut = m['shortcut']?.toString() ?? '';
      if (shortcut.isNotEmpty) {
        result[m['id']?.toString() ?? ''] = shortcut;
      }
    }
    return result;
  }

  // ==================== 缓存过期天数（非关键，缺省/错误默认 1 天） ====================

  /// 缓存过期天数（单位：天），-1 表示永不过期。
  ///
  /// 从 `cache.json` 的 `expireDays` 段读取；没有该配置或 JSON 错误时，全部默认 1 天。
  ({int emoji, int avatar, int image, int medal}) get cacheExpireDays {
    const fallback = 1;
    int dayOf(Object? v) {
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? fallback;
    }

    final map = _cache?['expireDays'] as Map<String, dynamic>?;
    if (map == null) {
      return (
        emoji: fallback,
        avatar: fallback,
        image: fallback,
        medal: fallback,
      );
    }
    return (
      emoji: dayOf(map['emoji']),
      avatar: dayOf(map['avatar']),
      image: dayOf(map['image']),
      medal: dayOf(map['medal']),
    );
  }

  // ==================== 全局快捷键（非关键，JSON 失败返回空） ====================

  Map<String, String> get globalShortcuts {
    final map = _shortcuts?['global'] as Map<String, dynamic>?;
    if (map == null || map.isEmpty) return const {};
    return map.map((k, v) => MapEntry(k, v.toString()));
  }
}
