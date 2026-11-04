import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:mtbbs/api/home/space/export.dart' as space_api;
import 'package:mtbbs/auth/providers/auth_provider.dart';
import 'package:mtbbs/config/build_config.dart';
import 'package:mtbbs/core/app/app_paths.dart';
import 'package:mtbbs/core/app/session_registry.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/utils/clipboard_helper.dart';
import 'package:mtbbs/core/settings/settings_repository.dart';
import 'package:mtbbs/core/utils/formatters.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/core/utils/url_router.dart';
import 'package:mtbbs/models/special_thanks.dart';
import 'package:mtbbs/models/user_profile.dart';
import 'package:mtbbs/pages/settings/models/about_settings.dart';
import 'package:mtbbs/pages/settings/widgets/dialogs.dart';
import 'package:mtbbs/platform/optional/file_pick.dart';
import 'package:mtbbs/platform/optional/file_save.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/services/data_portability.dart';
import 'package:mtbbs/services/update_service.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';
import 'package:mtbbs/widgets/common/user_avatar.dart';
import 'package:mtbbs/widgets/dialog/confirm_dialog.dart';
import 'package:mtbbs/widgets/dialog/text_input_dialog.dart';

part 'about_page_author.dart';
part 'about_page_data.dart';
part 'about_page_view.dart';

/// 关于页 — 应用标识、作者、相关链接、版本信息与特别鸣谢。
///
/// 鸣谢名单来自 `assets/config/thanks.json`，改内容不需要动代码；
/// 作者资料按 [authorUid] 从站点动态获取（首次取到后持久化，之后只读缓存）。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key, this.showAppBar = true});

  /// 宽屏设置页把本页放进右栏时传 false（外层已有自己的框架）
  final bool showAppBar;

  /// 开发者 UID：作者在 MT 论坛与 52pojie 都有账号。
  ///
  /// 当前浏览站点是 52pojie 时用它的 UID，其它情况（MT 论坛 / 未知站点）用 MT 的。
  static const String authorUidMt = '88062';
  static const String authorUid52 = '2284282';
  static const String site52Host = 'www.52pojie.cn';

  /// 开发者所属站点：跟随"当前站点是否为 52pojie"
  ///
  /// 单独标注站点后，头像地址、个人空间链接与请求的 Referer 标识都按该站点生成，
  /// 即使当前正在浏览别的站点也能正确取到对应论坛的资源；
  /// 未来增加其它论坛的作者/鸣谢时，各自带自己的 host 即可。
  static String get authorSiteHost => SiteStore.instance.host == site52Host
      ? site52Host
      : SpecialThanks.defaultSiteHost;

  /// 作者在该站点的 UID
  static String get authorUid =>
      SiteStore.instance.host == site52Host ? authorUid52 : authorUidMt;

  /// 作者所属站点的兜底地址（用户把该站点从配置里删掉时使用）
  static String get authorBaseUrl => authorSiteHost == site52Host
      ? 'https://www.52pojie.cn'
      : 'https://bbs.binmt.cc';

  /// 开源仓库（构建注入的更新源优先，未注入回落上游）
  static String get repoUrl => BuildConfig.repoUrl;

  /// 应用介绍帖
  static const String introUrl = 'https://bbs.binmt.cc/thread-169295-1-1.html';

  /// 应用图标位图（`mipmap-xxxhdpi/ic_launcher.png` 的副本，见 docs/16）
  static const String iconAsset = 'assets/icon/app_icon.png';

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  /// 只加载一次，避免主题切换等 rebuild 重复读 assets
  late final Future<List<SpecialThanks>> _thanks = SpecialThanks.load();

  /// 应用图标的累计旋转圈数；点一下随机叠加，交给 AnimatedRotation 平滑过渡
  double _turns = 0;
  final math.Random _random = math.Random();

  /// 开发者选项解锁手势：未解锁时连点 [_unlockNeedTaps] 次（相邻间隔 ≤2s）解锁
  static const int _unlockNeedTaps = 7;
  int _unlockTaps = 0;
  DateTime? _lastUnlockTapAt;

  /// 开发者资料（首次从站点获取后持久化，之后读缓存）
  UserProfile? _author;

  /// 当前 [_author] 对应的站点（切换站点后需重新加载，避免显示别的站的资料）
  String? _authorLoadedHost;

  @override
  void initState() {
    super.initState();
    _loadAuthor();
  }

  /// 供 part 扩展使用（扩展无法直接访问受保护的 setState）
  void _setState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  @override
  Widget build(BuildContext context) => _buildPage(context);
}
