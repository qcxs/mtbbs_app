import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:mtbbs/core/utils/logger.dart';

/// 特别鸣谢条目 — 由 `assets/config/thanks.json` 配置，改内容无需动代码。
///
/// 字段：`username`（用户名）、`uid`（用于渲染头像）、`title`（帖子标题）、
/// `url`（帖子链接）、`note`（备注）、`site`（所属站点 host，缺省为 MT 论坛）。
/// `site` 决定头像地址、链接打开与请求标识（Referer）归属哪个站点，
/// 后续新增其它论坛的用户无需改代码。
class SpecialThanks {
  const SpecialThanks({
    required this.username,
    required this.uid,
    required this.title,
    required this.url,
    this.note = '',
    this.siteHost = defaultSiteHost,
  });

  /// 用户昵称
  final String username;

  /// 论坛 uid，交给头像组件解析头像地址
  final String uid;

  /// 帖子标题
  final String title;

  /// 帖子链接
  final String url;

  /// 备注（一句话说明为什么要感谢 TA）
  final String note;

  /// 所属站点 host（决定头像/链接的请求归属）
  final String siteHost;

  /// 缺省站点：鸣谢与作者目前都来自 MT 论坛
  static const String defaultSiteHost = 'bbs.binmt.cc';

  /// 配置文件路径
  static const String assetPath = 'assets/config/thanks.json';

  factory SpecialThanks.fromJson(Map<String, dynamic> json) => SpecialThanks(
    username: json['username']?.toString() ?? '',
    uid: json['uid']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    url: json['url']?.toString() ?? '',
    note: json['note']?.toString() ?? '',
    siteHost: (json['site']?.toString().trim().isNotEmpty ?? false)
        ? json['site'].toString().trim()
        : defaultSiteHost,
  );

  /// 从 assets 读取鸣谢列表。
  ///
  /// 文件缺失、JSON 非法或字段类型异常都只记日志并返回空列表 ——
  /// 鸣谢属于装饰性内容，不能因为配置写错就让关于页打不开。
  static Future<List<SpecialThanks>> load() async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(SpecialThanks.fromJson)
          .where((e) => e.username.isNotEmpty || e.title.isNotEmpty)
          .toList();
    } catch (e) {
      AppLogger.w('SpecialThanks', '加载 $assetPath 失败：$e');
      return const [];
    }
  }
}
