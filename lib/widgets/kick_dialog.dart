import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import '../auth/providers/auth_provider.dart';
import '../services/api_service.dart';
import '../api/forum/viewthread/action/export.dart' as action_api;
import '../api/forum/viewthread/action/parse.dart' as action_parse;

/// 显示踢帖对话框
///
/// [kickUrl] 踢帖弹窗 URL
/// 返回 true 表示踢帖成功
Future<bool?> showKickDialog(
  BuildContext context,
  String baseUrl,
  String kickUrl,
) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _KickDialogContent(kickUrl: kickUrl),
  );
}

class _KickDialogContent extends StatefulWidget {
  final String kickUrl;
  const _KickDialogContent({required this.kickUrl});

  @override
  State<_KickDialogContent> createState() => _KickDialogContentState();
}

class _KickDialogContentState extends State<_KickDialogContent> {
  final Dio _dio = ApiService().dio;
  action_parse.KickFormData? _formData;
  bool _loading = true;
  String? _error;
  bool _submitting = false;
  final _reasonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadForm();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadForm() async {
    try {
      final formData = await action_api.fetchKickDialog(_dio, widget.kickUrl);
      if (!mounted) return;
      setState(() {
        _formData = formData;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    if (_formData == null) return;

    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先登录')));
      return;
    }

    setState(() => _submitting = true);

    try {
      final data = <String, dynamic>{
        'formhash': _formData!.formhash,
        'tid': _formData!.tid,
        'handlesubmit': 'yes',
      };
      final reason = _reasonController.text.trim();
      if (reason.isNotEmpty) {
        data['reason'] = reason;
      }

      final result = await action_api.doKick(_dio, _formData!.action, data);
      if (!mounted) return;

      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message.isNotEmpty ? result.message : '操作成功'),
          ),
        );
        Navigator.of(context).pop(true);
      } else {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message.isNotEmpty ? result.message : '操作失败'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('网络错误: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      constraints: const BoxConstraints(maxWidth: 420),
      title: const Text('踢帖'),
      content: _buildContent(),
      actions: [
        TextButton(
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _loading || _error != null || _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('确定'),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const SizedBox(
        width: 60,
        height: 60,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_error != null) {
      return Text('加载失败: $_error', style: const TextStyle(color: Colors.red));
    }

    if (_formData == null) {
      return const Text('无法获取踢帖信息');
    }

    return SizedBox(
      width: double.maxFinite,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '当前踢帖数: ${_formData!.currentKicks} / ${_formData!.maxKicks}',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 4),
          Text(
            '注意: 踢帖将把帖子从列表中移除，请合理使用。',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 12),
          const Text('踢帖理由:', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 4),
          TextField(
            controller: _reasonController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: '请输入踢帖理由（可选）',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.all(8),
              isDense: true,
            ),
            enabled: !_submitting,
          ),
        ],
      ),
    );
  }
}
