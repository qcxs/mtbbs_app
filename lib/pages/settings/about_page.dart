import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/api/home/space/export.dart' as space_api;
import 'package:mtbbs/config/build_config.dart';
import 'package:mtbbs/core/app/session_registry.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/utils/clipboard_helper.dart';
import 'package:mtbbs/core/utils/database_helper.dart';
import 'package:mtbbs/core/utils/formatters.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/core/utils/url_router.dart';
import 'package:mtbbs/models/special_thanks.dart';
import 'package:mtbbs/models/user_profile.dart';
import 'package:mtbbs/pages/settings/models/about_settings.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/services/update_service.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';
import 'package:mtbbs/widgets/common/user_avatar.dart';

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

  /// 开源仓库
  static const String repoUrl = BuildConfig.repoUrl;

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

  /// 开发者空间地址（固定指向作者所属站点）
  String get _authorSpaceUrl =>
      '${SessionRegistry.instance.baseUrlForHost(AboutPage.authorSiteHost) ?? AboutPage.authorBaseUrl}'
      '/home.php?mod=space&uid=${AboutPage.authorUid}&do=profile';

  /// 等级展示文本：优先「等级 + 头衔」，都为空时退回用户组
  String get _authorLevelText {
    final a = _author;
    if (a == null) return '';
    final parts = [
      a.level,
      a.customTitle,
    ].where((s) => s.trim().isNotEmpty).toList();
    return parts.isNotEmpty ? parts.join(' ') : a.userGroup;
  }

  /// 签名展示文本：签名是 BBCode，这里去掉标记只留纯文本（卡片仅两行）
  String get _authorSignatureText {
    final a = _author;
    if (a == null) return '';
    return a.signature.replaceAll(RegExp(r'\[[^\[\]]*\]'), '').trim();
  }

  @override
  void initState() {
    super.initState();
    _loadAuthor();
  }

  /// 加载开发者资料：先读持久化缓存，缺失时按 UID 抓取一次并写回
  Future<void> _loadAuthor() async {
    // 固定本次加载所用的站点与 UID，避免加载途中切换站点导致串号
    final host = AboutPage.authorSiteHost;
    final uid = AboutPage.authorUid;
    _authorLoadedHost = host;
    final key = 'aboutAuthorProfile_$host';
    final cached = await DatabaseHelper.instance.getSetting(key);
    if (cached != null && cached.isNotEmpty) {
      try {
        final map = jsonDecode(cached) as Map<String, dynamic>;
        if (mounted) setState(() => _author = UserProfile.fromMap(map));
        return;
      } catch (_) {
        // 缓存损坏则走网络重新获取
      }
    }
    try {
      // 作者资料固定在作者所属站点获取：用该站点的作用域 Dio，
      // 头像/页面请求携带的目标站点标识（Cookie、Referer）不会跟着当前站点漂移
      final dio = await ApiService().scopedDio(
        host: host,
        baseUrl: SessionRegistry.instance.baseUrlForHost(host) ??
            AboutPage.authorBaseUrl,
      );
      final raw = await space_api.getUserProfile(
        dio,
        uid: uid,
        // 作者资料是「进入关于页」附带的非关键请求：命中人机验证 / 防火墙时
        // 不能弹全局验证页（会盖在关于页上、且此请求并非用户主动发起）。
        // 打上「已处理」标记，让拦截器直接返回原响应，静默失败保留占位即可。
        options: Options(extra: {kInterstitialHandledFlag: true}),
      );
      if (raw['success'] != true || raw['profile'] == null) return;
      final profile = UserProfile.fromMap(
        (raw['profile'] as Map).cast<String, dynamic>(),
      );
      await DatabaseHelper.instance.setSetting(
        key,
        jsonEncode(profile.toMap()),
      );
      if (mounted) setState(() => _author = profile);
    } catch (e) {
      AppLogger.w('ABOUT', '作者信息获取失败: $e');
    }
  }

  /// 随机方向转 0.5~1.5 圈
  void _spinIcon() {
    final delta = 0.5 + _random.nextDouble();
    setState(() => _turns += _random.nextBool() ? delta : -delta);
  }

  /// 图标点击：已解锁开发者选项 → 直接进入；未解锁 → 转个圈并累计次数，满
  /// [_unlockNeedTaps] 次解锁（相邻两次超过 2 秒则重新计数）。
  void _onIconTap() {
    final settings = context.read<SettingsProvider>();
    if (settings.developerMode) {
      context.push('/settings/developer');
      return;
    }
    _spinIcon();
    final now = DateTime.now();
    if (_lastUnlockTapAt == null ||
        now.difference(_lastUnlockTapAt!) > const Duration(seconds: 2)) {
      _unlockTaps = 0;
    }
    _lastUnlockTapAt = now;
    _unlockTaps++;
    final left = _unlockNeedTaps - _unlockTaps;
    if (left > 0) {
      showToast('再点击 $left 次进入开发者选项');
    } else {
      _unlockTaps = 0;
      settings.setDeveloperMode(true);
      showToast('已解锁开发者选项，再次点击图标即可进入');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    // 切换站点后作者身份（UID/所属站点）会变，重新读该站点的资料
    if (_authorLoadedHost != AboutPage.authorSiteHost) {
      _author = null;
      _loadAuthor();
    }
    final hash = BuildConfig.commitHash;
    final shortHash = hash.length > 7 ? hash.substring(0, 7) : hash;
    // 未注入时 buildTime 为 0，显示占位而非 1970
    final buildTime = BuildConfig.buildTime > 0
        ? formatDateTimeFull(
            DateTime.fromMillisecondsSinceEpoch(
              BuildConfig.buildTime * 1000,
              isUtc: true,
            ).toLocal(),
          )
        : 'N/A';

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(title: const Text('关于'), centerTitle: true)
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          _header(cs),

          _sectionTitle('作者'),
          _authorCard(cs),

          _sectionTitle('相关链接'),
          _card([
            _linkTile(
              icon: Icons.article_outlined,
              title: '应用介绍',
              subtitle: '《使用 Flutter 开发的 MT 论坛 app》',
              onTap: () => _openLink(AboutPage.introUrl),
            ),
            const Divider(height: 1, indent: 56),
            _linkTile(
              icon: Icons.code,
              title: 'GitHub 仓库',
              subtitle: AboutPage.repoUrl,
              onTap: () => _openLink(AboutPage.repoUrl),
              trailing: IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: '复制地址',
                onPressed: () async {
                  await ClipboardHelper.write(AboutPage.repoUrl);
                  if (context.mounted) {
                    showToast('仓库地址已复制', duration: const Duration(seconds: 1));
                  }
                },
              ),
            ),
            const Divider(height: 1, indent: 56),
            _linkTile(
              icon: Icons.description_outlined,
              title: '开源许可',
              subtitle: 'GPL-3.0，二改须开源并注明原作者',
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'MTBBS',
                applicationVersion: BuildConfig.versionName,
                applicationLegalese: '© MTBBS contributors',
              ),
            ),
          ]),

          _sectionTitle('版本信息'),
          _card([
            _infoTile('当前版本', BuildConfig.versionName),
            // 最新版本来自检测更新：有值即表示检测成功（失败保持原样）
            _latestVersionTile(),
            _infoTile('构建号', '${BuildConfig.versionCode}'),
            _infoTile('构建提交', shortHash),
            _infoTile('构建时间', buildTime),
            // 更新相关项来自 aboutPageSettings() —— 与设置搜索的索引**同一份数据源**：
            // 新增/改文案只动一处，不会再出现「页面里有、搜索却搜不到」（见 docs/07 #51）
            for (final item in aboutPageSettings()) ...[
              const Divider(height: 1, indent: 16),
              item.build(context, settings),
            ],
          ]),

          FutureBuilder<List<SpecialThanks>>(
            future: _thanks,
            builder: (context, snapshot) {
              final entries = snapshot.data ?? const <SpecialThanks>[];
              if (entries.isEmpty) return const SizedBox.shrink();
              return _thanksSection(cs, entries);
            },
          ),
        ],
      ),
    );
  }

  /// 顶部应用标识
  Widget _header(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 4),
      child: Column(
        children: [
          // 图标位图自带圆角与透明角，无需再裁切或描边；点一下随机转个角度；
          // 连点 7 次解锁开发者选项，解锁后单击即进入（见 _onIconTap）
          GestureDetector(
            onTap: _onIconTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedRotation(
              turns: _turns,
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              child: Image.asset(
                AboutPage.iconAsset,
                width: 72,
                height: 72,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'MTBBS',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'v${BuildConfig.versionName} (${BuildConfig.versionCode})',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(
            'Discuz 论坛客户端 · 支持 Android / Windows',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// 作者卡片：头像 + 昵称 + 等级，点击进入论坛个人空间
  ///
  /// 资料来自 `_author`（按 UID 动态获取并持久化）；未取到时只显示头像与占位。
  Widget _authorCard(ColorScheme cs) {
    final nickname = _author?.nickname ?? '';
    final level = _authorLevelText;
    final signature = _authorSignatureText;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openLink(_authorSpaceUrl),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              UserAvatar(
                uid: AboutPage.authorUid,
                nickname: nickname,
                radius: 28,
                siteHost: AboutPage.authorSiteHost,
                tapAction: AvatarTapAction.none,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            nickname.isEmpty ? '—' : nickname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (level.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: cs.secondaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              level,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: cs.onSecondaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    _siteBadge(cs, AboutPage.authorSiteHost),
                    if (signature.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        signature,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: cs.outline),
            ],
          ),
        ),
      ),
    );
  }

  /// 特别鸣谢：左侧头像 + 用户名，右侧上标题下备注，整行点击打开链接
  Widget _thanksSection(ColorScheme cs, List<SpecialThanks> entries) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('特别鸣谢'),
        _card([
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 68),
            _thanksTile(cs, entries[i]),
          ],
        ]),
      ],
    );
  }

  Widget _thanksTile(ColorScheme cs, SpecialThanks entry) {
    return InkWell(
      onTap: () => _openLink(entry.url),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // 左侧：头像（点击整行时冒泡到 InkWell，故头像自身不接管点击）
            UserAvatar(
              uid: entry.uid,
              nickname: entry.username,
              radius: 20,
              siteHost: entry.siteHost,
              tapAction: AvatarTapAction.none,
            ),
            const SizedBox(width: 12),
            // 左侧：用户名 + 所属站点标识
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.username,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  _siteBadge(cs, entry.siteHost),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // 右侧：上标题、下备注
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.title,
                    maxLines: 2,
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: cs.onSurface),
                  ),
                  if (entry.note.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.note,
                      maxLines: 2,
                      textAlign: TextAlign.end,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 用户所属站点标识（如 MT论坛）：头像、链接与 Referer 都按该站点归属
  Widget _siteBadge(ColorScheme cs, String host) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.forum_outlined, size: 10, color: cs.onSurfaceVariant),
          const SizedBox(width: 3),
          Text(
            SessionRegistry.instance.siteNameForHost(host),
            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// 优先用 URL 路由匹配站内页面，匹配不到（或属于其他站点）再交给内置浏览器
  void _openLink(String url) {
    if (url.isEmpty) return;
    // resolveTarget 会为"已配置且已支持作用域"的站点补齐 site 参数，
    // 因此鸣谢里的 MT 论坛帖子/用户页在其它站点下也能直接进 App（只读）
    final target = UrlRouter.resolveTarget(url);
    if (target != null) context.push(target);
  }

  Widget _sectionTitle(String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _linkTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: trailing ?? Icon(Icons.chevron_right, color: cs.outline),
      onTap: onTap,
    );
  }

  Widget _card(List<Widget> children) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _infoTile(String label, String value) {
    return ListTile(
      dense: true,
      title: Text(label, style: const TextStyle(fontSize: 13)),
      trailing: SelectableText(value, style: const TextStyle(fontSize: 13)),
    );
  }

  /// 最新版本行 —— 取值来自检测更新结果，未检测到 / 检测失败时显示占位
  Widget _latestVersionTile() {
    return ValueListenableBuilder(
      valueListenable: UpdateService.instance.latestRelease,
      builder: (context, latest, _) => _infoTile(
        '最新版本',
        latest?.tagName.isNotEmpty == true ? latest!.tagName : '—',
      ),
    );
  }
}
