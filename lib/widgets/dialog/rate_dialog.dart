import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import 'package:mtbbs/auth/providers/auth_provider.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/api/forum/viewthread/action/export.dart' as action_api;
import 'package:mtbbs/api/forum/viewthread/action/parse.dart' as action_parse;
import 'package:mtbbs/widgets/common/toast_utils.dart';

/// 显示评分对话框
///
/// [rateUrl] 评分弹窗 URL（调用方用 tid+pid 直接拼接）
/// 返回 true 表示评分成功
Future<bool?> showRateDialog(BuildContext context, String rateUrl) {
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

  // 各评分项的自定义输入框（唯一分值来源；选项点击后填充到此输入框）
  final Map<String, TextEditingController> _scoreControllers = {};

  // 理由（可选、可自定义，预设理由用于快捷填充）
  final TextEditingController _reasonController = TextEditingController();
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
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadForm() async {
    try {
      final formData = await action_api.fetchRateDialog(_dio, widget.rateUrl);
      if (!mounted) return;
      setState(() {
        _formData = formData;
        _loading = false;
        // 每个评分项都用一个输入框承载分值（选项/自定义都写入这里）
        for (final item in formData.items) {
          _scoreControllers[item.inputName] = TextEditingController();
        }
      });
    } catch (e) {
      if (!mounted) return;
      final msg = (e is FormatException ? e.message : e.toString());
      showToast(msg);
      Navigator.of(context).pop();
    }
  }

  Future<void> _submit() async {
    if (_formData == null) return;

    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      showToast('请先登录');
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
        'handlekey': 'rate',
      };

      // 添加评分项：输入框是唯一分值来源（选项点击后已填充到输入框），空则 0
      for (final item in _formData!.items) {
        final val = _scoreControllers[item.inputName]?.text.trim() ?? '';
        data[item.inputName] = val.isNotEmpty ? val : '0';
      }

      // 理由（可选、可自定义，空则不上送）
      final reason = _reasonController.text.trim();
      if (reason.isNotEmpty) {
        data['reason'] = reason;
      }

      // 通知作者（Discuz 标准 checkbox，勾选提交 sendreasonpm=on）
      if (_formData!.hasNotifyAuthor) {
        data['sendreasonpm'] = _notifyAuthor ? 'on' : '0';
      }

      final result = await action_api.doRate(_dio, _formData!.action, data);
      if (!mounted) return;

      if (result.success) {
        showToast(result.message.isNotEmpty ? result.message : '评分成功');
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _submitting = false;
          _submitError = result.message;
        });
        showToast(result.message.isNotEmpty ? result.message : '评分失败');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = e.toString();
      });
      showToast('网络错误: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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

    // 极端情况：所有评分项均不可用（今日额度用完 / 区间与选项均无正值）
    final items = _formData!.items;
    final exhausted = items.isNotEmpty && items.every((i) => !_canRate(i));

    return AlertDialog(
      constraints: const BoxConstraints(maxWidth: 420),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Text(
        '评分',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 今日评分已用完提示
            if (exhausted)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '今日评分额度已用完',
                  style: TextStyle(fontSize: 12, color: cs.onErrorContainer),
                ),
              ),
            // 提交错误提示
            if (_submitError != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _submitError!,
                  style: TextStyle(fontSize: 12, color: cs.onErrorContainer),
                ),
              ),
            // 评分项列表
            ...items.map((item) => _buildRateItem(item, cs)),
            // 理由（可选、可自定义；有预设理由时可点选快捷填充）
            const Text(
              '理由',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _reasonController,
              enabled: !_submitting,
              decoration: InputDecoration(
                isDense: true,
                hintText: '理由（可选）',
                prefixIcon: const Icon(Icons.chat_bubble_outline, size: 16),
                prefixIconConstraints: const BoxConstraints(minWidth: 32),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
            ),
            if (_formData!.reasonOptions.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _formData!.reasonOptions
                    .map(
                      (r) => ActionChip(
                        label: Text(r, style: const TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                        onPressed: _submitting
                            ? null
                            : () => setState(() => _reasonController.text = r),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 8),
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
          onPressed: _loading || _error != null || _submitting || exhausted
              ? null
              : _submit,
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

  /// 单项是否可评：今日还有剩余额度，且区间/选项存在可取正值
  bool _canRate(action_parse.RateItem i) {
    if (i.todayRemaining <= 0) return false;
    final hasPositiveOption = i.options.any((o) {
      final v = int.tryParse(o.replaceAll('+', '')) ?? 0;
      return v > 0;
    });
    return i.max > 0 || hasPositiveOption;
  }

  /// 单个评分项：名称/剩余/区间 + 填充式选项（ActionChip 点击填充输入框）+ 输入框
  Widget _buildRateItem(action_parse.RateItem item, ColorScheme cs) {
    final usable = _canRate(item);
    final controller = _scoreControllers[item.inputName];
    final remainingColor = item.todayRemaining <= 0
        ? cs.error
        : cs.onSurfaceVariant;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // 今日剩余总是显示（0 用红色提示额度用完）
              Text(
                item.todayRemaining > 0
                    ? '今日剩余 ${item.todayRemaining}'
                    : '今日剩余 0',
                style: TextStyle(fontSize: 11, color: remainingColor),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '评分区间 ${item.min} ~ ${item.max}',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          // 填充式选项：点击后填入输入框（输入框是唯一数据源，不设独立选中态）
          if (item.options.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: item.options.map((o) {
                final optVal = int.tryParse(o.replaceAll('+', ''));
                // 额度用完或 0 值选项禁用
                final disabled =
                    _submitting || !usable || (optVal != null && optVal <= 0);
                return ActionChip(
                  label: Text(o, style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                  onPressed: disabled
                      ? null
                      : () => setState(() => controller?.text = o),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 8),
          // 分值输入框（今日额度用完时禁用）
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            enabled: !_submitting && usable,
            decoration: InputDecoration(
              isDense: true,
              hintText: item.options.isNotEmpty
                  ? '分值（点击选项或手动输入）'
                  : '${item.min} ~ ${item.max}',
              prefixIcon: const Icon(Icons.edit_outlined, size: 15),
              prefixIconConstraints: const BoxConstraints(minWidth: 32),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
            ),
          ),
          if (!usable)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '今日额度已用完，不可评分',
                style: TextStyle(fontSize: 10, color: cs.error),
              ),
            ),
        ],
      ),
    );
  }
}
