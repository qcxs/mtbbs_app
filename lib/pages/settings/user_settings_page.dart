import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/core/app/session_registry.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';
import 'package:mtbbs/widgets/common/user_avatar.dart';

/// 用户设置（以账号为键）
///
/// 列出所有站点的已登录账号，点进某个账号后配置"这个账号的行为"：
/// 目前有「设为该站点的默认用户」，后续（自动签到等）都挂在账号详情里，
/// 而不是按站点平铺配置 —— 行为最终都归属到具体账号。
///
/// 视觉与设置主页保持一致：纯背景、无填充卡片、分隔线分组；
/// 宽屏按可用宽度自动分列，避免一行拉得太长。
class UserSettingsPage extends StatefulWidget {
  const UserSettingsPage({super.key});

  @override
  State<UserSettingsPage> createState() => _UserSettingsPageState();
}

class _UserSettingsPageState extends State<UserSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sites = SiteStore.instance.sites;

    return Scaffold(
      appBar: AppBar(title: const Text('用户设置'), centerTitle: true),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = constraints.maxWidth - 24;
          final columns = constraints.maxWidth >= 980
              ? 3
              : constraints.maxWidth >= 660
              ? 2
              : 1;
          const gap = 8.0;
          final tileWidth = (contentWidth - gap * (columns - 1)) / columns;

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                child: Text(
                  '按账号设置行为。跨站浏览始终只读，写操作需先切换到目标站点。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              if (sites.isEmpty)
                _buildEmpty(cs, '还没有配置站点')
              else
                for (final site in sites)
                  ..._buildSiteSection(cs, site, tileWidth, gap),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmpty(ColorScheme cs, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.people_outline, size: 44, color: cs.outlineVariant),
          const SizedBox(height: 10),
          Text(text, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  List<Widget> _buildSiteSection(
    ColorScheme cs,
    Site site,
    double tileWidth,
    double gap,
  ) {
    final isCurrent = SiteStore.instance.host == site.host;
    final accounts = SessionRegistry.instance.accountsFor(site.host);
    final def = SessionRegistry.instance.defaultAccountFor(site.host);

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: isCurrent ? cs.primary : cs.outline,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                site.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (isCurrent) ...[
              const SizedBox(width: 6),
              _textTag(cs, '当前'),
            ],
            const Spacer(),
            Text(
              '默认：${def ?? '游客'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
      if (accounts.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 4, 12),
          child: Text(
            '暂无已登录账号，切换到该站点登录后可在此设置',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        )
      else
        Wrap(
          spacing: gap,
          runSpacing: 2,
          children: [
            for (final account in accounts)
              _buildAccountTile(
                cs,
                site,
                account,
                def == account.username,
                tileWidth,
              ),
          ],
        ),
      const SizedBox(height: 10),
    ];
  }

  Widget _buildAccountTile(
    ColorScheme cs,
    Site site,
    SiteAccount account,
    bool isDefault,
    double width,
  ) {
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await context.push(
            '/settings/user?host=${Uri.encodeComponent(site.host)}'
            '&username=${Uri.encodeComponent(account.username)}',
          );
          if (mounted) setState(() {});
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              UserAvatar(
                uid: account.uid,
                nickname: account.username,
                radius: 19,
                siteHost: site.host,
                tapAction: AvatarTapAction.none,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            account.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (isDefault) ...[
                          const SizedBox(width: 6),
                          _textTag(cs, '该站默认'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'UID ${account.uid}',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: cs.outline),
            ],
          ),
        ),
      ),
    );
  }

  /// 纯文字小标签（无填充色，避免在纯背景上显得跳）
  Widget _textTag(ColorScheme cs, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
      ),
    );
  }
}

/// 单个账号的行为设置
class UserSettingsDetailPage extends StatefulWidget {
  const UserSettingsDetailPage({
    super.key,
    required this.host,
    required this.username,
  });

  final String host;
  final String username;

  @override
  State<UserSettingsDetailPage> createState() => _UserSettingsDetailPageState();
}

class _UserSettingsDetailPageState extends State<UserSettingsDetailPage> {
  bool get _isDefault =>
      SessionRegistry.instance.defaultAccountFor(widget.host) ==
      widget.username;

  String? get _otherDefault {
    final def = SessionRegistry.instance.defaultAccountFor(widget.host);
    return def == null || def == widget.username ? null : def;
  }

  String get _uid {
    for (final a in SessionRegistry.instance.accountsFor(widget.host)) {
      if (a.username == widget.username) return a.uid;
    }
    return '';
  }

  Future<void> _setDefault(bool value) async {
    await SessionRegistry.instance.setDefaultAccount(
      widget.host,
      value ? widget.username : null,
    );
    if (!mounted) return;
    setState(() {});
    showToast(
      value
          ? '已将 ${widget.username} 设为该站点默认用户'
          : '已改为游客身份（打开该站点链接时不登录）',
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final site = SessionRegistry.instance.siteForHost(widget.host);

    return Scaffold(
      appBar: AppBar(title: const Text('账号设置'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // 账号信息（纯背景，无填充卡片）
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                UserAvatar(
                  uid: _uid,
                  nickname: widget.username,
                  radius: 26,
                  siteHost: widget.host,
                  showBorder: true,
                  tapAction: AvatarTapAction.none,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (_isDefault) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: cs.outlineVariant),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '该站默认',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        site?.name ?? widget.host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 24),

          _sectionTitle(cs, '跨站身份'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _isDefault,
            onChanged: (v) => _setDefault(v),
            title: const Text('该站点默认用户', style: TextStyle(fontSize: 14)),
            subtitle: Text(
              '在其它站点打开本站链接时，以这个账号只读浏览',
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            secondary: Icon(
              Icons.badge_outlined,
              size: 20,
              color: cs.onSurfaceVariant,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 4, top: 2),
            child: Text(
              _otherDefault == null
                  ? '关闭后以游客身份读取（游客可能看不到需要登录的内容）。每个站点只能有一个默认用户。'
                  : '当前默认用户是 $_otherDefault，开启后将替换它。每个站点只能有一个默认用户。',
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(ColorScheme cs, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}
