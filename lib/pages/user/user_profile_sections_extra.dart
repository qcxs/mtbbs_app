part of 'user_profile_page.dart';

/// 用户主页 — 积分与个性化区块（积分卡片 / 个性签名 / 自定义头衔 / 勋章）。
///
/// 通过 `part of` 与 user_profile_page.dart 共享库内私有成员。
extension on _UserProfilePageState {
  /// 积分与活跃数据 — 合并显示，自适应排列
  Widget _buildPointsSection() {
    final points = _profile!['points'] as Map<String, dynamic>?;
    final stats = _profile!['stats'] as Map<String, dynamic>?;
    // 人气为移动模板独有：资料行（profile）或统计行（stats）任一处提供
    final popularity =
        _profile!['popularity']?.toString() ?? stats?['popularity']?.toString();
    if (points == null &&
        stats == null &&
        (popularity == null || popularity.isEmpty)) {
      return const SizedBox.shrink();
    }

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
      // 积分记录入口（仅自己）：好评/金币/信誉 → 对应类型的积分记录页
      // （`spacecp&ac=credit&op=log` 只能查看当前登录用户，故仅在本人空间可点）
      final isSelf =
          !_session.temporary &&
          (widget.uid == 'self' ||
              context.select<AuthProvider, String>((a) => a.uid) == widget.uid);

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
        onTap: isSelf ? () => _openAppPath('/credit-log?exttype=1') : null,
      );
      add(
        '金币',
        points['goldCoins']?.toString() ?? '0',
        Icons.workspace_premium_outlined,
        const Color(0xFFFFC107),
        onTap: isSelf ? () => _openAppPath('/credit-log?exttype=2') : null,
      );
      add(
        '信誉',
        points['credit']?.toString() ?? '0',
        Icons.verified_outlined,
        const Color(0xFF2196F3),
        onTap: isSelf ? () => _openAppPath('/credit-log?exttype=3') : null,
      );
    }
    // 人气（移动模板独有；PC 无 → 不显示）——由头部右侧移入瓦片区
    if (popularity != null && popularity.isNotEmpty) {
      add(
        '人气',
        popularity,
        Icons.local_fire_department_outlined,
        const Color(0xFFE53935),
      );
    }
    if (stats != null) {
      // 按数据源差异渲染：PC 模板提供「好友/回帖/主题/分享」，
      // 克米移动模板提供「好友/回复/帖子」（人气已并入上方瓦片）——
      // 缺哪个就不渲染哪个。
      if (stats['friends'] != null) {
        add(
          '好友',
          stats['friends'].toString(),
          Icons.people_outlined,
          const Color(0xFFE91E63),
          onTap: () => _openAppPath('/friends?uid=$uid'),
        );
      }
      if (stats['replies'] != null) {
        add(
          '回帖',
          stats['replies'].toString(),
          Icons.reply_outlined,
          const Color(0xFF00BCD4),
          onTap: () => _openAppPath('/my-threads?type=reply&uid=$uid'),
        );
      }
      if (stats['threads'] != null) {
        add(
          '主题',
          stats['threads'].toString(),
          Icons.article_outlined,
          const Color(0xFF9C27B0),
          onTap: () => _openAppPath('/my-threads?uid=$uid'),
        );
      }
      if (stats['shares'] != null) {
        add(
          '分享',
          stats['shares'].toString(),
          Icons.share_outlined,
          const Color(0xFFFF5722),
        );
      }
    }

    // 关注 / 粉丝（由头部移入统计区）：移动模板给出计数；PC 模板无计数时
    // 值显示「—」，入口仍保留（点进对应列表）。
    final following = _profile!['following']?.toString();
    final followers = _profile!['followers']?.toString();
    if (_uidNum != null || following != null) {
      add(
        '关注',
        following ?? '—',
        Icons.visibility_outlined,
        const Color(0xFF3F51B5),
        onTap: () => _openAppPath('/follow?type=following&uid=$uid'),
      );
    }
    if (_uidNum != null || followers != null) {
      add(
        '粉丝',
        followers ?? '—',
        Icons.people_outline,
        const Color(0xFF00897B),
        onTap: () => _openAppPath('/follow?type=follower&uid=$uid'),
      );
    }

    if (tiles.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      color: _cs.surface,
      child: _buildTileRow(tiles),
    );
  }

  // ==================== 私信（头部右侧） ====================

  /// 私信 —— 置于头部右侧空白区（人气/关注/粉丝已并入下方统计瓦片）。
  ///
  /// 人气为移动独有（已并入瓦片）；私信仅他人视角（自己主页入口在「我的」页）。
  /// 关注/已关注：他人视角提供，文案随状态切换（Discuz 原名「收听」）。
  List<Widget> _headerActions() {
    if (widget.uid.isEmpty) return const [];
    final isSelf =
        !_session.temporary &&
        (context.select<AuthProvider, String>((a) => a.uid) == widget.uid);
    final followed = _profile!['followed'] == true;

    return [
      if (!isSelf && _uidNum != null)
        _actionItem(
          icon: followed
              ? Icons.person_add_alt_1
              : Icons.person_add_alt_1_outlined,
          label: _followBusy ? '处理中' : (followed ? '已关注' : '关注'),
          onTap: _followBusy ? null : _toggleFollow,
        ),
      _actionItem(
        icon: Icons.forum_outlined,
        label: '留言板',
        onTap: () {
          if (_guardReadOnly()) return;
          final nickname = _profile!['nickname'] as String? ?? '';
          context.push(
            '/user/${widget.uid}/wall'
            '${nickname.isEmpty ? '' : '?nickname=${Uri.encodeComponent(nickname)}'}',
          );
        },
      ),
      if (!isSelf && _uidNum != null)
        _actionItem(
          icon: Icons.mail_outline,
          label: '私信',
          onTap: () {
            if (_guardReadOnly()) return;
            final nickname = _profile!['nickname'] as String? ?? '';
            context.push(
              '/pm/chat?touid=${widget.uid}'
              '&username=${Uri.encodeComponent(nickname)}',
            );
          },
        ),
    ];
  }

  /// 关注 / 取消关注（仅他人主页）。
  ///
  /// - 未关注 → 直接请求（无参数操作，不弹确认框），成功后按钮变「已关注」
  /// - 已关注 → 二次确认后取消关注（与收藏删除等破坏性操作一致）
  /// - 已关注状态下的「已关注」按钮图标为实心，未关注为描边
  Future<void> _toggleFollow() async {
    if (_followBusy || _profile == null) return;
    if (!context.read<AuthProvider>().isLoggedIn) {
      showToast('请先登录');
      return;
    }
    if (_guardReadOnly()) return;

    final followed = _profile!['followed'] == true;
    final nickname = _profile!['nickname'] as String? ?? '该用户';
    if (followed) {
      final ok = await showConfirmDialog(
        context,
        title: '取消关注',
        message: '确定不再关注 $nickname 吗？',
        confirmText: '取消关注',
        danger: true,
      );
      if (ok != true) return;
    }

    _setState(() => _followBusy = true);
    try {
      final result = followed
          ? await follow_api.unfollowUser(_dio, uid: widget.uid)
          : await follow_api.followUser(
              _dio,
              uid: widget.uid,
              formhash: _profile!['followHash']?.toString() ?? '',
            );
      if (!mounted) return;
      if (result['success'] == true) {
        _setState(() {
          _followBusy = false;
          _profile!['followed'] = !followed;
        });
        showToast(followed ? '已取消关注' : '已关注');
      } else {
        _setState(() => _followBusy = false);
        showToast(result['message']?.toString() ?? '操作失败');
      }
    } catch (e) {
      if (!mounted) return;
      _setState(() => _followBusy = false);
      showToast('操作失败：$e');
    }
  }

  /// 单个操作项 —— 胶囊样式（图标 + 文案 + 计数），固定宽度以便排成两列网格
  Widget _actionItem({
    required IconData icon,
    required String label,
    String? count,
    VoidCallback? onTap,
  }) {
    final hasCount = count != null && count.isNotEmpty;
    // 可点击项在文案下加下划线（与积分瓦片一致），暗示可点
    final tappable = onTap != null;
    final pill = Container(
      width: 106,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: _cs.onSurfaceVariant),
          const SizedBox(width: 5),
          Container(
            decoration: tappable
                ? BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: _cs.onSurfaceVariant.withValues(alpha: 0.35),
                        width: 1,
                      ),
                    ),
                  )
                : null,
            padding: tappable ? const EdgeInsets.only(bottom: 1) : null,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: _cs.onSurfaceVariant),
            ),
          ),
          if (hasCount) ...[
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                count,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _cs.onSurface,
                ),
              ),
            ),
          ],
        ],
      ),
    );
    if (!tappable) return pill;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: pill,
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
              style: context.appTypography.mono.copyWith(
                fontSize: 11,
                color: _cs.onSurfaceVariant,
                height: 1.5,
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
