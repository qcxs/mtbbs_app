import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/config/build_config.dart';
import 'package:mtbbs/pages/settings/models/settings_model.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/services/update_service.dart';
import 'package:mtbbs/widgets/dialog/update_dialog.dart';

/// 关于入口 — 单独一行，不参与分组（「通用错峰间隔」已归入站点与网络组）
List<SettingsModel> aboutSettings() => [
  NormalSetting(
    title: '关于',
    icon: Icons.info_outline,
    subtitle: 'MTBBS v${BuildConfig.versionName}+${BuildConfig.versionCode}',
    onTap: (ctx, s) => ctx.push('/settings/about'),
  ),
];

/// 关于**页内**的设置与动作 —— 由关于页自己渲染，**同一份**也被设置搜索收录。
///
/// 关键：只维护这一份。关于页改了这里就跟着改，**不需要**去搜索页再登记一次——
/// "另有一份清单"正是遗漏的根源（见 docs/07 #51）。
///
/// 未注入更新源（本地构建）时整组不显示：这些包不检查更新。
List<SettingsModel> aboutPageSettings() {
  final service = UpdateService.instance;
  if (!service.isConfigured) return const [];
  return [
    // 自动检查由渠道策略决定（beta / debug 默认关闭）
    if (service.autoCheckEnabled)
      SwitchSetting(
        title: '自动检查更新',
        subtitle: '启动时检查 GitHub 上是否有新版本（1 小时内不重复）',
        icon: Icons.cloud_download_outlined,
        value: (s) => s.autoCheckUpdate,
        onChanged: (ctx, s, v) => s.setAutoCheckUpdate(v),
      ),
    // 手动检查按渠道策略提供（便于 beta / debug 排查）
    if (service.manualCheckEnabled)
      NormalSetting(
        title: '检查更新',
        subtitle: '检查 GitHub 上的最新版本',
        icon: Icons.system_update_alt,
        trailingBuilder: (context, _) => ValueListenableBuilder<bool>(
          valueListenable: UpdateService.instance.checking,
          builder: (context, checking, _) => checking
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  Icons.chevron_right,
                  color: Theme.of(context).colorScheme.outline,
                ),
        ),
        onTap: (ctx, s) => checkForUpdate(ctx, isAuto: false, settings: s),
      ),
  ];
}
