part of 'thread_view_page.dart';

/// 帖子浏览页 — 布局与区块构建。
///
/// 通过 `part of` 与 thread_view_page.dart 共享库内私有成员。
extension on _ThreadViewPageState {
  // ==================== 布局 ====================

  Widget _buildWideLayout() {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              if (_data!.title.isNotEmpty) _buildTitleSection(),
              if (_data!.mainPost != null) _buildMainPostSection(),
            ],
          ),
        ),
        Container(width: 1, color: cs.outlineVariant),
        Expanded(flex: 2, child: _buildCommentColumn()),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    final currentPosts = _commentPages[_currentPage];
    if ((currentPosts == null || currentPosts.isEmpty) &&
        _data!.mainPost == null &&
        !_pageLoading) {
      return const EmptyView(text: '暂无数据');
    }
    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          if (_data!.title.isNotEmpty)
            SliverToBoxAdapter(child: _buildTitleSection()),
          if (_data!.mainPost != null) ...[
            SliverToBoxAdapter(child: _buildMainPostSection()),
            SliverToBoxAdapter(child: const Divider(height: 1)),
            // 评论区锚点 — 窄屏"滚动到评论区"的目标
            SliverToBoxAdapter(
              child: SizedBox(key: _commentAnchorKey, height: 1),
            ),
          ],
          SliverPersistentHeader(
            pinned: true,
            delegate: CommentHeaderDelegate(
              child: CommentSection.buildHeader(
                context: context,
                currentPage: _currentPage,
                totalPages: _totalPages,
                pageLoading: _pageLoading,
                onPrev: _currentPage > 1
                    ? () => _goToPage(_currentPage - 1)
                    : null,
                onNext: _currentPage < _totalPages
                    ? () => _goToPage(_currentPage + 1)
                    : null,
                onPageTap: _showPagePicker,
                onRefresh: _refreshCurrentPage,
              ),
            ),
          ),
          SliverToBoxAdapter(child: _buildCommentContent()),
          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.of(context).padding.bottom + 60),
          ),
        ],
      ),
    );
  }

  // ==================== 评论区 ====================

  Widget _buildCommentContent() {
    final currentPosts = _commentPages[_currentPage];
    if (currentPosts == null && _pageLoading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return CommentSection(
      posts: currentPosts ?? [],
      postKeys: _postKeys,
      currentPage: _currentPage,
      totalPages: _totalPages,
      pageLoading: _pageLoading,
      tid: widget.tid,
      opUid: _data?.mainPost?.uid ?? '',
      globalDisableStyle: _globalDisableStyle,
      onReply: (post) => _replyToPost(post),
      onRecommend: _handleRecommend,
      onPopupAction: (action, post) {
        switch (action) {
          case PostCardAction.showBbcode:
            _showBbcodeDialog(post);
          case PostCardAction.editPost:
            _editPost(post);
          case PostCardAction.viewTime:
            _fetchPostDetailInfo(post);
          case PostCardAction.rate:
            _handleRate(post);
        }
      },
    );
  }

  Widget _buildCommentColumn() {
    return Column(
      children: [
        CommentSection.buildHeader(
          context: context,
          currentPage: _currentPage,
          totalPages: _totalPages,
          pageLoading: _pageLoading,
          onPrev: _currentPage > 1 ? () => _goToPage(_currentPage - 1) : null,
          onNext: _currentPage < _totalPages
              ? () => _goToPage(_currentPage + 1)
              : null,
          onPageTap: _showPagePicker,
          onRefresh: _refreshCurrentPage,
        ),
        const Divider(height: 1),
        Expanded(child: SingleChildScrollView(child: _buildCommentContent())),
      ],
    );
  }

  // ==================== 主帖 ====================

  Widget _buildMainPostSection() {
    final post = _data!.mainPost!;
    return MainPostSection(
      post: post,
      isLoaded: _mainPostLoaded,
      isLiked: _liked,
      tid: widget.tid,
      globalDisableStyle: _globalDisableStyle,
      onTap: () => _setState(() => _mainPostLoaded = true),
      onRecommend: () => _handleRecommend(post),
      onPopupAction: (action) {
        switch (action) {
          case PostCardAction.showBbcode:
            _showBbcodeDialog(post);
          case PostCardAction.editPost:
            _editPost(post);
          case PostCardAction.viewTime:
            _fetchPostDetailInfo(post);
          case PostCardAction.rate:
            _handleRate(post);
        }
      },
    );
  }

  // ==================== 杂项组件 ====================

  // ==================== 迷你编辑器 ====================

  /// 底部内嵌迷你编辑器（评论 / 回复某评论，可收起读帖、可展开为完整版）
  Widget _buildMiniEditor() {
    return MiniEditorBar(
      contentCtl: _editorSession.contentCtl,
      toolbarContext: MiniToolbarContext.thread,
      hintText: _replyTargetPid != null ? '回复评论…' : '说点什么…',
      submitting: _editorSubmitting,
      autofocus: true,
      onSubmit: _submitMiniEditor,
      onImage: _showForumImageUpload,
      onMtImage: _showMtImage,
      onCollapse: _collapseEditor,
      onExpandToFull: _expandToFull,
      targetLabel: _replyTargetName != null ? '回复 ${_replyTargetName}' : null,
      onTapTarget: _replyTargetPid != null ? _showReplyTargetPreview : null,
    );
  }

  Widget _buildReplyBar() {
    final cs = Theme.of(context).colorScheme;
    if (_data == null) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 6,
        bottom: MediaQuery.of(context).padding.bottom + 6,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: _favoriting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _favorited ? Icons.bookmark : Icons.bookmark_border,
                    size: 20,
                    color: _favorited ? cs.primary : cs.onSurfaceVariant,
                  ),
            tooltip: _favorited ? '已收藏' : '收藏帖子（可备注）',
            onPressed: _favoriting ? null : _handleFavorite,
          ),
          // 点赞（对帖子的操作，移到收藏旁）
          IconButton(
            icon: Icon(
              _liked ? Icons.thumb_up : Icons.thumb_up_outlined,
              size: 20,
              color: _liked ? cs.primary : cs.onSurfaceVariant,
            ),
            tooltip: _liked ? '已点赞' : '点赞',
            onPressed: () {
              final mainPost = _data?.mainPost;
              if (mainPost != null) _handleRecommend(mainPost);
            },
          ),
          // 评分（文字入口，移到收藏旁）
          if (_data?.mainPost != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _handleRate(_data!.mainPost!),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '评分',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Icon(Icons.reply_rounded, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: _navigateComment,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '说点什么...',
                  style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: Icon(Icons.send_rounded, color: cs.onSurfaceVariant),
            onPressed: _navigateComment,
          ),
        ],
      ),
    );
  }

  Widget _buildTitleSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Text(
        _data!.title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
      ),
    );
  }
}
