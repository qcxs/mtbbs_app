import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/config/build_config.dart';
import 'package:mtbbs/core/utils/clipboard_helper.dart';
import 'package:mtbbs/core/utils/url_router.dart';
import 'package:mtbbs/models/special_thanks.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';
import 'package:mtbbs/widgets/common/user_avatar.dart';

/// 关于页 — 应用标识、作者、相关链接、版本信息与特别鸣谢。
///
/// 鸣谢名单来自 `assets/config/thanks.json`，改内容不需要动代码；
/// 其余条目是稳定信息（作者、仓库、介绍帖），直接写在常量里。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  /// 开发者
  static const String authorName = '青春向上';
  static const String authorUid = '88062';
  static const String authorLevel = 'Lv.7 博士生';
  static const String authorSignature = '年少不知号贵，猥琐升级，勿浪！';
  static const String authorSpaceUrl =
      'https://bbs.binmt.cc/home.php?mod=space&uid=88062&do=profile';

  /// 开源仓库
  static const String repoUrl = 'https://github.com/qcxs/mtbbs_app';

  /// 应用介绍帖
  static const String introUrl = 'https://bbs.binmt.cc/thread-169295-1-1.html';

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  /// 只加载一次，避免主题切换等 rebuild 重复读 assets
  late final Future<List<SpecialThanks>> _thanks = SpecialThanks.load();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hash = BuildConfig.commitHash;
    final shortHash = hash.length > 7 ? hash.substring(0, 7) : hash;

    return Scaffold(
      appBar: AppBar(title: const Text('关于'), centerTitle: true),
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
            _infoTile('版本名', BuildConfig.versionName),
            _infoTile('构建号', '${BuildConfig.versionCode}'),
            _infoTile('构建提交', shortHash),
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
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(Icons.forum, size: 36, color: cs.onPrimaryContainer),
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
  Widget _authorCard(ColorScheme cs) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openLink(AboutPage.authorSpaceUrl),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              UserAvatar(
                uid: AboutPage.authorUid,
                nickname: AboutPage.authorName,
                radius: 28,
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
                            AboutPage.authorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
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
                            AboutPage.authorLevel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: cs.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      AboutPage.authorSignature,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
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
              tapAction: AvatarTapAction.none,
            ),
            const SizedBox(width: 12),
            // 左侧：用户名
            Expanded(
              flex: 3,
              child: Text(
                entry.username,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
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

  /// 优先用 URL 路由匹配站内页面，匹配不到（或属于其他站点）再交给内置浏览器
  void _openLink(String url) {
    if (url.isEmpty) return;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      final routeResult = UrlRouter.parse(url);
      if (routeResult.appPath != null && !routeResult.isOtherSite) {
        context.push(routeResult.appPath!);
      } else {
        context.push(
          '/browser?url=${Uri.encodeComponent(url)}&intercept=false',
        );
      }
    } else {
      context.push(url);
    }
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
}
