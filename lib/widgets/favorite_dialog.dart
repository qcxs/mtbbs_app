import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import '../auth/providers/auth_provider.dart';
import '../services/api_service.dart';
import '../api/forum/viewthread/action/export.dart' as action_api;
import '../api/forum/viewthread/action/parse.dart' as action_parse;

/// 显示收藏对话框
///
/// [favUrl] 收藏弹窗 URL
/// 返回 true 表示收藏成功
Future<bool?> showFavoriteDialog(
  BuildContext context,
  String baseUrl,
  String favUrl,
) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _FavoriteDialogContent(favUrl: favUrl),
  );
}

class _FavoriteDialogContent extends StatefulWidget {
  final String favUrl;
  const _FavoriteDialogContent({required this.favUrl});

  @override
  State<_FavoriteDialogContent> createState() => _FavoriteDialogContentState();
}

class _FavoriteDialogContentState extends State<_FavoriteDialogContent> {
  final Dio _dio = ApiService().dio;
  action_parse.FavoriteFormData? _formData;
  bool _loading = true;
  String? _error;
  bool _submitting = false;
  final _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadForm();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadForm() async {
    try {
      final formData = await action_api.fetchFavoriteDialog(
        _dio,
        widget.favUrl,
      );
      if (!mounted) return;
      setState(() {
        _formData = formData;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = (e is FormatException ? e.message : e.toString());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      Navigator.of(context).pop();
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
        'favoritesubmit': 'true',
        'formhash': _formData!.formhash,
        'handlekey': 'favorite_add',
      };
      final note = _noteController.text.trim();
      if (note.isNotEmpty) {
        data['description'] = note;
      }

      final result = await action_api.doFavorite(
        _dio,
        _formData!.action,
        data,
        formId: _formData!.formId,
      );
      if (!mounted) return;

      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message.isNotEmpty ? result.message : '收藏成功'),
          ),
        );
        Navigator.of(context).pop(true);
      } else {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message.isNotEmpty ? result.message : '收藏失败'),
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
      title: const Text('收藏'),
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

    if (_formData == null) {
      return const Text('无法获取收藏信息');
    }

    return SizedBox(
      width: double.maxFinite,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '收藏帖子',
            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          const Text('备注（可选）:', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 4),
          TextField(
            controller: _noteController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: '添加备注信息',
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
