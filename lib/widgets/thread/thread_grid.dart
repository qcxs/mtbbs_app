import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/controllers/thread_list_controller.dart';
import 'package:mtbbs/models/thread_item.dart';
import 'package:mtbbs/models/thread_detail.dart';
import 'package:mtbbs/widgets/thread/thread_card.dart';
import 'package:mtbbs/widgets/dialog/page_jump_dialog.dart';
import 'package:mtbbs/widgets/layout/state_views.dart';

part 'thread_grid_build.dart';
part 'thread_grid_paginator.dart';

/// 通用帖子列表网格
///
/// 功能：
/// - 下拉刷新
/// - 分页器（上一页 / 页码 / 下一页），切换时滚动到顶部
/// - 响应式列数（手机 1 列，平板 2 列，桌面 3 列）
/// - 加载中骨架屏
/// - 空状态、错误状态显示
class ThreadGrid extends StatefulWidget {
  final ThreadListController controller;
  final bool visible;
  final void Function(ThreadItem item)? onViewReplies;
  final Map<int, List<PostItem>> expandedReplies;
  final Set<int> loadingReplies;
  final Map<int, String> errorReplies;

  /// 空列表时的提示文案 / 图标（搜索等场景可定制）
  final String emptyText;
  final IconData emptyIcon;

  /// 关键词高亮：非空时透传给 [ThreadCard]（搜索场景使用）
  final String highlight;

  const ThreadGrid({
    super.key,
    required this.controller,
    this.visible = true,
    this.onViewReplies,
    this.expandedReplies = const {},
    this.loadingReplies = const {},
    this.errorReplies = const {},
    this.emptyText = '暂无帖子',
    this.emptyIcon = Icons.inbox_outlined,
    this.highlight = '',
  });

  @override
  State<ThreadGrid> createState() => _ThreadGridState();
}

class _ThreadGridState extends State<ThreadGrid>
    with AutomaticKeepAliveClientMixin {
  bool _everLoaded = false;
  final ScrollController _scrollController = ScrollController();
  List<ThreadItem>? _lastItems;
  int _lastPage = 1;
  LoadState _lastState = LoadState.initial;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onStateChanged);
  }

  @override
  void didUpdateWidget(ThreadGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onStateChanged);
      widget.controller.addListener(_onStateChanged);
    }
    if (!oldWidget.visible && widget.visible) {
      _checkLoad();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.visible) {
      _checkLoad();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onStateChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _checkLoad() {
    if (_everLoaded) return;
    if (widget.controller.state == LoadState.initial) {
      _everLoaded = true;
      widget.controller.loadInitial();
    }
  }

  void _onStateChanged() {
    if (!mounted) return;
    final ctrl = widget.controller;
    // 数据或状态任一变化时触发重建。列表用「对象身份」判断而非条数：
    // 刷新后新数据条数可能完全相同，只比条数会漏判 → UI 保留旧内容。
    if (identical(ctrl.items, _lastItems) &&
        ctrl.page == _lastPage &&
        ctrl.state == _lastState)
      return;
    _lastItems = ctrl.items;
    _lastPage = ctrl.page;
    _lastState = ctrl.state;
    setState(() {});
  }

  /// 页面切换时滚动到顶部
  void _handlePageChange() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // AutomaticKeepAliveClientMixin 要求 build 调用 super.build 以注册 keep-alive
    super.build(context);
    return _buildPage(context);
  }

  // ==================== 响应式列数 ====================

  int _crossAxisCount(double width) {
    if (width >= 900) return 3;
    if (width >= 600) return 2;
    return 1;
  }

  double _gridSpacing(double width) {
    return width >= 600 ? 8 : 0;
  }
}
