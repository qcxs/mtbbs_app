import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/api/home/pm/export.dart' as pm_api;
import 'package:mtbbs/auth/providers/auth_provider.dart';
import 'package:mtbbs/config/toolbar_config.dart';
import 'package:mtbbs/core/app/emoji_loader.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/pages/editor/mt_image_sheet.dart';
import 'package:mtbbs/pages/message/pm_message_bubble.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/services/mt_image_hosting.dart';
import 'package:mtbbs/widgets/bbcode/bbcode_controller.dart';
import 'package:mtbbs/widgets/common/page_actions.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';
import 'package:mtbbs/widgets/dialog/confirm_dialog.dart';
import 'package:mtbbs/widgets/editor/mini_editor_bar.dart';
import 'package:mtbbs/widgets/layout/page_error_widget.dart';
import 'package:mtbbs/widgets/layout/state_views.dart';

part 'pm_chat_page_compose.dart';
part 'pm_chat_page_load.dart';
part 'pm_chat_page_poll.dart';

/// 私信聊天页 —— 与单个用户的会话（气泡式）
///
/// 数据来自 `lib/api/home/pm/`：首屏拉**最新一页**，向上滚动按
/// `olderPage` 逐页追加更旧消息（Discuz 的 page 从最旧页 1 递增到最新）。
/// 正文是服务端渲染过的 HTML，经 `Html2BBCode` 还原后用 [PostHtmlWidget]
/// 渲染，与帖子正文同一套链路。
///
/// **滚动锚点**：列表用 `reverse: true`，以底部（最新消息）为锚点。向上加载
/// 旧消息时内容追加在视觉顶部，不会顶动可视区；即使旧消息里的图片懒加载后
/// 才撑开高度，也不会引起错位（正向列表按"高度差补偿"做的话则会错位）。
///
/// **实时轮询**：Discuz 没有"增量拉新消息"接口，只能按 [_kPollInterval]
/// 周期重拉最新一页、按 pmid 去重后追加。仅在页面挂载且应用处于前台时轮询，
/// 切后台/离开页面即停，避免无谓请求。
///
/// **限流保护**：整页重拉是本页最贵的请求（完整 HTML），连续失败按
/// [_kBackoffSteps] 退避；一旦收到 403/429 说明已被站点限流，立即暂停自动
/// 刷新（继续按原频率重试只会延长封禁窗口），由用户手动刷新解除。
class PmChatPage extends StatefulWidget {
  /// 对方 uid
  final String touid;

  /// 对方用户名（列表/主页跳转时已知，用于首屏标题，可空）
  final String? username;

  const PmChatPage({super.key, required this.touid, this.username});

  @override
  State<PmChatPage> createState() => _PmChatPageState();
}

class _PmChatPageState extends State<PmChatPage> with WidgetsBindingObserver {
  final _items = <Map<String, dynamic>>[];

  /// 本地乐观发送的消息（服务端尚未确认），渲染在列表末尾。
  /// 每条含 `_localId` / `_status`(sending|sent|failed) / `isMine` / `bbcode` / `time` / `_error`。
  final _pending = <Map<String, dynamic>>[];
  final _inputCtl = BBCodeController();
  final _mtImageHosting = MtImageHosting();
  final _scrollCtl = ScrollController();

  String _username = '';
  String _formhash = '';
  int _olderPage = 0;
  bool _hasOlder = false;
  bool _loading = true;
  bool _loadingOlder = false;
  String? _error;

  /// 是否有消息正在发送（轮询避让用）
  bool get _sending => _pending.any((m) => m['_status'] == 'sending');

  /// 是否有发送失败、尚未处理的消息。
  /// 失败消息只存在内存里（`_pending`），退出页面即丢失，因此返回时需二次确认。
  bool get _hasFailedMessage => _pending.any((m) => m['_status'] == 'failed');

  Timer? _pollTimer;

  /// 轮询是否处于激活态（前台且页面存活）。定时器改为自调度后，用它判断
  /// 一次异步轮询返回时是否还应续排下一轮——切后台期间不得续命。
  bool _pollActive = false;
  bool _polling = false;

  /// 连续失败次数（成功一次即清零），决定下一轮的退避时长
  int _pollFailures = 0;

  /// 非空表示自动刷新已因限流暂停，内容即暂停原因；手动刷新解除
  String? _pollPausedReason;

  /// 本页是否已尝试加载过表情元数据（失败也不在每轮轮询里重试）
  bool _emojiRequested = false;

  /// 首屏/刷新在途的请求，供轮询等复用以避免重复整页请求
  Future<void>? _loadNewestInFlight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _username = widget.username ?? '';
    _loadNewest();
    _startPolling();
  }

  @override
  void dispose() {
    _stopPolling();
    WidgetsBinding.instance.removeObserver(this);
    _inputCtl.dispose();
    _scrollCtl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 前台才轮询：后台/未激活时停掉，恢复时立刻补一次
    if (state == AppLifecycleState.resumed) {
      _startPolling();
      _poll();
    } else {
      _stopPolling();
    }
  }

  /// 供 part 扩展使用（扩展无法直接访问受保护的 setState）
  void _setState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  @override
  Widget build(BuildContext context) {
    final title = _username.isNotEmpty ? _username : '与用户 ${widget.touid}';
    return PopScope(
      // 有发送失败的消息时拦一次返回：失败内容只存在本次会话，退出即丢失
      canPop: !_hasFailedMessage,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showConfirmDialog(
          context,
          title: '有发送失败的消息',
          message: '失败的消息只在本次会话中保留，退出后将丢失。确定退出？',
          confirmText: '退出',
          cancelText: '留下',
          danger: true,
        );
        if (leave == true && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: GestureDetector(
            onTap: () => context.push('/user/${widget.touid}'),
            child: Text(title, overflow: TextOverflow.ellipsis),
          ),
          actions: [
            PageActions(
              url: _pageUrl,
              onRefresh: _loadNewest,
              loading: _loading,
              copyLabel: '复制会话链接',
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(child: _buildBody()),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }
}
