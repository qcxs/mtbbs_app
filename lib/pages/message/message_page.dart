import 'package:flutter/material.dart';
import 'message_pm_tab.dart';
import 'message_mypost_tab.dart';
import 'message_system_tab.dart';

/// 消息页面 — 聚合私人消息 / 我的帖子 / 系统提醒
///
/// 路径: /message
/// 每个 Tab 独立管理加载状态和分页，各自封装在独立的 Widget 中。
/// AppBar 由 AppShell 提供，此处只返回内容体。
class MessagePage extends StatefulWidget {
  const MessagePage({super.key});

  @override
  State<MessagePage> createState() => _MessagePageState();
}

class _MessagePageState extends State<MessagePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtl;

  @override
  void initState() {
    super.initState();
    _tabCtl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabCtl,
            labelColor: Colors.deepPurple,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: Colors.deepPurple,
            tabs: const [
              Tab(text: '我的消息'),
              Tab(text: '我的帖子'),
              Tab(text: '系统提醒'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabCtl,
            children: const [PmTab(), MypostTab(), SystemTab()],
          ),
        ),
      ],
    );
  }
}
