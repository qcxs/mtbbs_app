import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import '../auth/providers/auth_provider.dart';
import '../services/api_service.dart';
import '../api/forum/viewthread/action/export.dart' as action_api;
import '../api/forum/viewthread/action/parse.dart' as action_parse;

/// 显示评分对话框
///
/// [rateUrl] 评分弹窗 URL
/// 返回 true 表示评分成功
Future<bool?> showRateDialog(
  BuildContext context,
  String baseUrl,
  String rateUrl,
) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _RateDialogContent(rateUrl: rateUrl),
  );
}

class _RateDialogContent extends StatefulWidget {
  final String rateUrl;
  const _RateDialogContent({required this.rateUrl});

  @override
  State<_RateDialogContent> createState() => _RateDialogContentState();
}

class _RateDialogContentState extends State<_RateDialogContent> {
  final Dio _dio = ApiService().dio;
  action_parse.RateFormData? _formData;
  bool _loading = true;
  String? _error;
  String? _submitError;
  bool _submitting = false;

  // 存储各评分项的输入值
  final Map<String, TextEditingController> _scoreControllers = {};
  final Map<String, String?> _scoreSelections = {};

  String? _selectedReason;
  bool _notifyAuthor = true;

  @override
  void initState() {
    super.initState();
    _loadForm();
  }

  @override
  void dispose() {
    for (final c in _scoreControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadForm() async {
    try {
      final formData = await action_api.fetchRateDialog(_dio, widget.rateUrl);
      if (!mounted) return;
      setState(() {
        _formData = formData;
        _loading = false;
        // 初始化评分项控制器
        for (final item in formData.items) {
          if (item.options.isEmpty) {
            _scoreControllers[item.inputName] = TextEditingController();
          } else {
            _scoreSelections[item.inputName] = item.options.isNotEmpty
                ? item.options.first
                : null;
          }
        }
        if (formData.reasonOptions.isNotEmpty) {
          _selectedReason = formData.reasonOptions.first;
        }
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

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      // 构建提交数据
      final data = <String, dynamic>{
        'formhash': _formData!.formhash,
        'tid': _formData!.tid,
        'pid': _formData!.pid,
        'handlesubmit': 'yes',
      };

      // 添加评分项
      for (final item in _formData!.items) {
        if (item.options.isNotEmpty) {
          data[item.inputName] = _scoreSelections[item.inputName] ?? '0';
        } else {
          final val = _scoreControllers[item.inputName]?.text.trim() ?? '';
          data[item.inputName] = val.isNotEmpty ? val : '0';
        }
      }

      // 添加理由
      if (_selectedReason != null) {
        data['reason'] = _selectedReason;
      }

      // 通知作者
      if (_formData!.hasNotifyAuthor) {
        data['noticeauthor'] = _notifyAuthor ? '1' : '0';
      }

      final result = await action_api.doRate(_dio, _formData!.action, data);
      if (!mounted) return;

      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message.isNotEmpty ? result.message : '评分成功'),
          ),
        );
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _submitting = false;
          _submitError = result.message;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message.isNotEmpty ? result.message : '评分失败'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = e.toString();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('网络错误: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AlertDialog(
        constraints: BoxConstraints(maxWidth: 420),
        content: SizedBox(
          width: 60,
          height: 60,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    if (_formData == null) {
      return AlertDialog(
        constraints: const BoxConstraints(maxWidth: 420),
        content: const Text('无法获取评分信息'),
      );
    }

    return AlertDialog(
      constraints: const BoxConstraints(maxWidth: 420),
      title: const Text('评分'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 提交错误提示
            if (_submitError != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _submitError!,
                  style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                ),
              ),
            // 评分项列表
            ..._formData!.items.map((item) => _buildRateItem(item)),
            const SizedBox(height: 12),
            // 理由下拉
            if (_formData!.reasonOptions.isNotEmpty) ...[
              const Text('理由:', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 4),
              DropdownButton<String>(
                value: _selectedReason,
                isExpanded: true,
                items: _formData!.reasonOptions
                    .map(
                      (r) => DropdownMenuItem(
                        value: r,
                        child: Text(r, style: const TextStyle(fontSize: 13)),
                      ),
                    )
                    .toList(),
                onChanged: _submitting
                    ? null
                    : (v) => setState(() => _selectedReason = v),
              ),
              const SizedBox(height: 8),
            ],
            // 通知作者开关
            if (_formData!.hasNotifyAuthor)
              SwitchListTile(
                title: const Text('通知作者', style: TextStyle(fontSize: 13)),
                value: _notifyAuthor,
                dense: true,
                contentPadding: EdgeInsets.zero,
                onChanged: _submitting
                    ? null
                    : (v) => setState(() => _notifyAuthor = v),
              ),
          ],
        ),
      ),
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

  Widget _buildRateItem(action_parse.RateItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              item.name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: item.options.isNotEmpty
                ? DropdownButton<String>(
                    value: _scoreSelections[item.inputName],
                    isExpanded: true,
                    items: item.options
                        .map(
                          (o) => DropdownMenuItem(
                            value: o,
                            child: Text(
                              o,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _submitting
                        ? null
                        : (v) => setState(
                            () => _scoreSelections[item.inputName] = v,
                          ),
                  )
                : TextField(
                    controller: _scoreControllers[item.inputName],
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '${item.min}~${item.max}',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                    ),
                    enabled: !_submitting,
                  ),
          ),
          if (item.todayRemaining > 0)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                '剩余${item.todayRemaining}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ),
        ],
      ),
    );
  }
}
