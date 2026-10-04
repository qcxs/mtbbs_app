part of 'user_profile_page.dart';

/// 用户主页 — 展示区块与纯计算小工具。
///
/// 通过 `part of` 与 user_profile_page.dart 共享库内私有成员。
extension on _UserProfilePageState {
  // ==================== 用户头部 ====================

  Widget _buildHeader() {
    final p = _profile!;
    final nickname = p['nickname'] as String? ?? '未知';
    final uid = p['uid'] as String? ?? '';
    final online = p['online'] as bool? ?? false;
    final userGroup = _getNested(p, ['activity', 'userGroup']) as String?;
    final adminGroup = _getNested(p, ['activity', 'adminGroup']) as String?;
    // 等级（Lv.x）仅克米移动模板提供，与用户组拼在一起展示
    final level = p['level'] as String?;
    final group = [
      if (level != null && level.isNotEmpty) level,
      if (adminGroup != null && adminGroup.isNotEmpty) adminGroup,
      if (adminGroup == null || adminGroup.isEmpty) ...[
        if (userGroup != null && userGroup.isNotEmpty) userGroup,
      ],
    ].join(' ');

    // 关注/粉丝/人气/私信 —— 置于头部右侧空白区（窄屏换行右对齐）
    final actions = _headerActions();
    final avatar = UserAvatar(
      uid: uid,
      nickname: nickname,
      radius: 32,
      tapAction: AvatarTapAction.viewAvatar,
    );
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              nickname,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            if (online)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: onlineColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '在线',
                  style: TextStyle(fontSize: 11, color: onlineColor),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'UID: $uid',
          style: TextStyle(fontSize: 13, color: _cs.onSurfaceVariant),
        ),
        if (group.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: levelColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              group,
              style: const TextStyle(
                fontSize: 12,
                color: levelColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );

    return Container(
      padding: const EdgeInsets.all(20),
      color: _cs.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 宽屏：操作项放头部右侧空白；窄屏：换到下方右对齐，避免挤压昵称
          if (actions.isNotEmpty && constraints.maxWidth >= 480) {
            return Row(
              children: [
                avatar,
                const SizedBox(width: 16),
                Expanded(child: info),
                const SizedBox(width: 12),
                SizedBox(
                  width: 220,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: actions,
                  ),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  avatar,
                  const SizedBox(width: 16),
                  Expanded(child: info),
                ],
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: 220,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: actions,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  // ==================== 积分与活跃卡片（统一自适应） ====================

  /// 统一的信息块 — 图标 + 标签 + 数值
  Widget _infoTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    VoidCallback? onTap,
  }) {
    final clickable = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 3),
            Container(
              decoration: clickable
                  ? BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: _cs.onSurfaceVariant.withValues(alpha: 0.35),
                          width: 1,
                        ),
                      ),
                    )
                  : null,
              padding: clickable ? const EdgeInsets.only(bottom: 1) : null,
              child: Text(
                label,
                style: TextStyle(fontSize: 11, color: _cs.onSurfaceVariant),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 自适应瓦片行 — 根据可用宽度自动计算每行数量，等宽填充
  Widget _buildTileRow(List<Widget> tiles) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    const spacing = 4.0;
    // 期望每个 tile 约 90px 宽，以此计算列数
    const targetTileWidth = 90.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final cols = ((availableWidth + spacing) / (targetTileWidth + spacing))
            .floor()
            .clamp(1, tiles.length);
        // 实际 tile 宽度等分填充行
        final tileWidth = (availableWidth - spacing * (cols - 1)) / cols;

        return Wrap(
          spacing: spacing,
          runSpacing: 4,
          children: tiles
              .map((t) => SizedBox(width: tileWidth, child: t))
              .toList(),
        );
      },
    );
  }

  /// 从 "5754 小时" 中提取数字
  double _extractHours(String? str) {
    if (str == null || str.isEmpty) return 0;
    final match = RegExp(r'([\d,.]+)').firstMatch(str);
    if (match == null) return 0;
    return _n(match.group(1));
  }

  double _n(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return parseDoubleWithComma(v);
  }

  // ==================== 活跃概况 ====================

  Widget _buildActivityInfo() {
    final activity = _profile!['activity'] as Map<String, dynamic>?;
    if (activity == null) return const SizedBox.shrink();

    final items = <MapEntry<String, String>>[];
    void add(String label, String? value) {
      if (value != null && value.isNotEmpty) {
        items.add(MapEntry(label, value));
      }
    }

    add('在线时间', activity['onlineTime'] as String?);
    add('注册时间', activity['registerTime'] as String?);
    add('最后访问', activity['lastVisit'] as String?);
    add('上次活动', activity['lastActivityTime'] as String?);
    add('上次发表', activity['lastPostTime'] as String?);

    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: _cs.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bar_chart_outlined,
                size: 16,
                color: _cs.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                '活跃概况',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      item.key,
                      style: TextStyle(
                        fontSize: 13,
                        color: _cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(item.value, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
