import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/models/managed_item.dart';

/// 默认配置加载器 — 从 `assets/config/defaults.json` 加载默认值
///
/// 只有站点配置加载失败时有硬编码回退（否则 App 无法启动），
/// 快捷键/工具栏/快捷链接等非关键项直接返回空。
class DefaultConfig {
  DefaultConfig._();
  static final DefaultConfig instance = DefaultConfig._();

  Map<String, dynamic>? _data;

  /// 是否已成功加载
  bool get isLoaded => _data != null;

  /// 从 assets 加载默认配置
  Future<void> load() async {
    try {
      final json = await rootBundle.loadString('assets/config/defaults.json');
      _data = jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {}
  }

  // ==================== 站点（关键，异常有回退） ====================

  /// 默认站点列表
  List<Site> get defaultSites {
    final list = _data?['sites'] as List<dynamic>?;
    if (list != null && list.isNotEmpty) {
      return list.map((j) => Site.fromJson(j as Map<String, dynamic>)).toList();
    }
    return [
      Site(
        name: 'MT论坛',
        baseUrl: 'https://bbs.binmt.cc',
        cdn: 'https://cdn-bbs.mt2.cn',
        loginPagePath: '/member.php?mod=logging&action=login',
        forums: {},
        defaultForumOrder: [],
      ),
      Site(
        name: '吾爱破解',
        baseUrl: 'https://www.52pojie.cn',
        cdn: 'https://static.52pojie.cn/',
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
    final perSite = _data?['shortcutLinks'] as Map<String, dynamic>?;
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
    final list = _data?['toolbar'] as List<dynamic>?;
    if (list == null) return [];
    return list.cast<Map<String, dynamic>>();
  }

  /// 生成默认的工具栏项列表（按 JSON 顺序），JSON 失败返回空
  List<ManagedItem> get defaultToolbarItems {
    final configs = toolbarConfigs;
    if (configs.isEmpty) return [];
    return configs.map((m) {
      return ManagedItem(
        id: m['id']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        visible: (m['visible'] as bool?) ?? true,
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
  /// 从 `cacheExpire` 段读取；没有该配置或 JSON 错误时，全部默认 1 天。
  ({int emoji, int avatar, int image, int medal}) get cacheExpireDays {
    const fallback = 1;
    int dayOf(Object? v) {
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? fallback;
    }

    final map = _data?['cacheExpire'] as Map<String, dynamic>?;
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
    final map = _data?['shortcuts'] as Map<String, dynamic>?;
    if (map == null || map.isEmpty) return const {};
    return map.map((k, v) => MapEntry(k, v.toString()));
  }
}
