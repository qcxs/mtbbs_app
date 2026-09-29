part of 'user_profile_page.dart';

/// 用户主页 — 积分与个性化区块（积分卡片 / 个性签名 / 自定义头衔 / 勋章）。
///
/// 通过 `part of` 与 user_profile_page.dart 共享库内私有成员。
extension on _UserProfilePageState {
  /// 积分与活跃数据 — 合并显示，自适应排列
  Widget _buildPointsSection() {
    final points = _profile!['points'] as Map<String, dynamic>?;
    final stats = _profile!['stats'] as Map<String, dynamic>?;
    if (points == null && stats == null) return const SizedBox.shrink();

    final uid = widget.uid;
    final tiles = <Widget>[];
    void add(
      String label,
      String value,
      IconData icon,
      Color color, {
      VoidCallback? onTap,
    }) {
      tiles.add(
        _infoTile(
          icon: icon,
          label: label,
          value: value,
          color: color,
          onTap: onTap,
        ),
      );
    }

    if (points != null) {
      add(
        '积分',
        points['credits']?.toString() ?? '0',
        Icons.monetization_on_outlined,
        const Color(0xFFFF9800),
        onTap: _showCreditDialog,
      );
      add(
        '好评',
        points['reputation']?.toString() ?? '0',
        Icons.thumb_up_outlined,
        const Color(0xFF4CAF50),
      );
      add(
        '金币',
        points['goldCoins']?.toString() ?? '0',
        Icons.workspace_premium_outlined,
        const Color(0xFFFFC107),
      );
      add(
        '信誉',
        points['credit']?.toString() ?? '0',
        Icons.verified_outlined,
        const Color(0xFF2196F3),
      );
    }
    if (stats != null) {
      add(
        '好友',
        stats['friends']?.toString() ?? '0',
        Icons.people_outlined,
        const Color(0xFFE91E63),
        onTap: () => context.push('/friends?uid=$uid'),
      );
      add(
        '回帖',
        stats['replies']?.toString() ?? '0',
        Icons.reply_outlined,
        const Color(0xFF00BCD4),
        onTap: () => context.push('/my-threads?type=reply&uid=$uid'),
      );
      add(
        '主题',
        stats['threads']?.toString() ?? '0',
        Icons.article_outlined,
        const Color(0xFF9C27B0),
        onTap: () => context.push('/my-threads?uid=$uid'),
      );
      add(
        '分享',
        stats['shares']?.toString() ?? '0',
        Icons.share_outlined,
        const Color(0xFFFF5722),
      );
    }

    if (tiles.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      color: _cs.surface,
      child: _buildTileRow(tiles),
    );
  }

  // ==================== 个性签名 ====================

  Widget _buildSignature() {
    final sig = _profile!['signature'] as String? ?? '';
    if (sig.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      color: _cs.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.format_quote, size: 16, color: _cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                '个性签名',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _cs.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Text(
                  _showRawSignature ? 'T̶' : 'T',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _showRawSignature ? _cs.error : _cs.onSurfaceVariant,
                  ),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: _showRawSignature ? '渲染 BBCode' : '显示原始 BBCode',
                onPressed: () =>
                    _setState(() => _showRawSignature = !_showRawSignature),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_showRawSignature)
            SelectableText(
              sig,
              style: TextStyle(
                fontSize: 11,
                color: _cs.onSurfaceVariant,
                height: 1.5,
                fontFamily: 'monospace',
              ),
            )
          else
            PostHtmlWidget(
              bbcode: sig,
              fontSize: 14,
              disabledTags: const {},
              autoDetectUrls: true,
            ),
        ],
      ),
    );
  }

  // ==================== 自定义头衔 ====================

  Widget _buildCustomTitle() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: _cs.surface,
      child: Row(
        children: [
          Icon(Icons.badge_outlined, size: 16, color: _cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            '头衔: ',
            style: TextStyle(fontSize: 13, color: _cs.onSurfaceVariant),
          ),
          Text(
            _profile!['customTitle'] as String? ?? '',
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ==================== 勋章 ====================

  Widget _buildMedals() {
    final medals = _profile!['medals'] as List<dynamic>? ?? [];
    if (medals.isEmpty) return const SizedBox.shrink();

    final medalWidgets = medals.map((m) {
      final medal = m as Map<String, dynamic>;
      final name = medal['name'] as String? ?? '';
      final icon = medal['icon'] as String? ?? '';
      return SizedBox(
        height: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 36,
                height: 36,
                child: icon.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: icon,
                        cacheManager: medalCacheManager,
                        fit: BoxFit.contain,
                      )
                    : Container(
                        color: _cs.surfaceContainerLow,
                        child: Icon(
                          Icons.emoji_events_outlined,
                          size: 18,
                          color: _cs.onSurfaceVariant,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: _cs.onSurfaceVariant,
                height: 1.2,
              ),
            ),
          ],
        ),
      );
    }).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      color: _cs.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.emoji_events_outlined,
                size: 16,
                color: _cs.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                '勋章 (${medals.length})',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildTileRow(medalWidgets),
        ],
      ),
    );
  }
}
