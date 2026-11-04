part of 'about_page.dart';

/// 页面视图 —— 头部、作者卡片、链接/数据管理/版本分组与鸣谢列表。
extension on _AboutPageState {
  Widget _buildPage(BuildContext context) {
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
                  final ok = await ClipboardHelper.write(AboutPage.repoUrl);
                  if (context.mounted) {
                    showToast(
                      ok ? '仓库地址已复制' : '复制到剪切板失败',
                      duration: const Duration(seconds: 1),
                    );
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

          _sectionTitle('数据管理'),
          _card([
            _linkTile(
              icon: Icons.save_outlined,
              title: '导出设置',
              subtitle: '应用设置 + 各站点设置（不含缓存）',
              onTap: _exportSettings,
            ),
            const Divider(height: 1, indent: 56),
            _linkTile(
              icon: Icons.settings_backup_restore_outlined,
              title: '导入设置',
              subtitle: '覆盖应用设置与各站点设置',
              onTap: _importSettings,
            ),
            const Divider(height: 1, indent: 56),
            _linkTile(
              icon: Icons.cookie_outlined,
              title: '导出账号 Cookie',
              subtitle: '各站点账号列表与 Cookie（可跨设备恢复登录）',
              onTap: _exportCookies,
            ),
            const Divider(height: 1, indent: 56),
            _linkTile(
              icon: Icons.file_download_outlined,
              title: '导入账号 Cookie',
              subtitle: '覆盖各站点账号的 Cookie',
              onTap: _importCookies,
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
