import 'package:flutter/material.dart';
import '../../controllers/thread_list_controller.dart';
import '../../widgets/thread_grid.dart';
import '../../services/api_service.dart';
import '../../api/home/mythread/export.dart' as my_thread_api;

/// 我的帖子/回复页面
class MyThreadPage extends StatefulWidget {
  /// 类型：null 或 '' 表示发帖，'reply' 表示回复
  final String? type;

  /// 目标用户 UID，为空表示当前登录用户
  final String? uid;

  const MyThreadPage({super.key, this.type, this.uid});

  @override
  State<MyThreadPage> createState() => _MyThreadPageState();
}

class _MyThreadPageState extends State<MyThreadPage> {
  late final ThreadListController _controller;

  String get _title {
    if (widget.type == 'reply') return '最近回复';
    if (widget.uid != null && widget.uid!.isNotEmpty) return 'Ta的帖子';
    return '我的帖子';
  }

  @override
  void initState() {
    super.initState();
    _controller = ThreadListController(
      fetchFn: ({required int page}) => my_thread_api.getMyThreads(
        ApiService().dio,
        page: page,
        uid: widget.uid,
        type: widget.type,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.refresh(),
          ),
        ],
      ),
      body: ThreadGrid(controller: _controller, visible: true),
    );
  }
}
