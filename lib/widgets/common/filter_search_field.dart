import 'package:flutter/material.dart';

/// 用户列表本地过滤：按用户名 / UID 做不区分大小写的包含匹配。
///
/// 关注/粉丝、好友、在线用户、小黑屋等页共用（原先各写一份逐字相同的实现）。
List<Map<String, dynamic>> filterUserItems(
  List<Map<String, dynamic>> items,
  String query,
) {
  if (query.isEmpty) return items;
  final q = query.toLowerCase();
  return items.where((item) {
    final username = (item['username'] as String? ?? '').toLowerCase();
    final uid = item['uid'] as String? ?? '';
    return username.contains(q) || uid.contains(q);
  }).toList();
}

/// 用户列表页的本地过滤搜索框（用户名 / UID）。
///
/// [query] 用于决定是否显示清除按钮；[onChanged] 已 trim。
class FilterSearchField extends StatelessWidget {
  const FilterSearchField({
    super.key,
    required this.controller,
    required this.query,
    required this.onChanged,
    this.hint = '搜索用户名或 UID…',
    this.padding = const EdgeInsets.fromLTRB(12, 8, 12, 4),
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final String hint;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: query.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onChanged: (v) => onChanged(v.trim()),
      ),
    );
  }
}
