import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/api/forum/viewthread/viewpid/export.dart' as viewpid_api;
import 'package:mtbbs/api/home/credit/export.dart' as credit_api;
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/core/utils/url_router.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/widgets/common/page_actions.dart';
import 'package:mtbbs/widgets/layout/load_more_footer.dart';
import 'package:mtbbs/widgets/layout/page_error_widget.dart';
import 'package:mtbbs/widgets/layout/state_views.dart';

/// 积分记录页（我的）
///
/// 仅展示**当前登录用户**的积分变更记录
/// （`home.php?mod=spacecp&ac=credit&op=log`）。支持按积分类型 / 收支 / 时间范围
/// 筛选，分页加载，触底自动加载更多。
class CreditLogPage extends StatefulWidget {
  /// 初始积分类型（`'0'`/空=不限，`'1'`=好评，`'2'`=金币，`'3'`=信誉）
  final String initialExttype;

  /// 初始操作类型代码（如 `PRC`，空=不限）
  final String initialOptype;

  const CreditLogPage({
    super.key,
    this.initialExttype = '0',
    this.initialOptype = '',
  });

  @override
  State<CreditLogPage> createState() => _CreditLogPageState();
}

class _CreditLogPageState extends State<CreditLogPage> {
  final _scrollController = ScrollController();
  final _items = <Map<String, dynamic>>[];
  int _page = 1;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;

  // 筛选条件
  String _exttype = '0'; // 0=不限 / 1=好评 / 2=金币 / 3=信誉
  String _income = '0'; // 0=不限 / 1=收入 / -1=支出
  String _optype = ''; // 操作类型代码（如 PRC，来自 URL/深链），空=不限
  DateTime? _start;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    _exttype = widget.initialExttype.isEmpty ? '0' : widget.initialExttype;
    _optype = widget.initialOptype;
    _scrollController.addListener(_onScroll);
    _fetch();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  String get _startStr => _start == null ? '' : _fmtDate(_start!);
  String get _endStr => _end == null ? '' : _fmtDate(_end!);

  static String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _fetch() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _page = 1;
    });

    try {
      final result = await credit_api.fetchCreditLog(
        ApiService().dio,
        page: 1,
        exttype: _exttype,
        income: _income,
        optype: _optype,
        starttime: _startStr,
        endtime: _endStr,
      );
      if (!mounted) return;

      if (result['success'] != true) {
        setState(() {
          _error = result['message'] as String? ?? '加载失败';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _items
          ..clear()
          ..addAll(_asItems(result['items']));
        _hasMore = result['hasMore'] == true;
        _page = 1;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      AppLogger.w('PAGE', 'CreditLogPage error: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final nextPage = _page + 1;
      final result = await credit_api.fetchCreditLog(
        ApiService().dio,
        page: nextPage,
        exttype: _exttype,
        income: _income,
        optype: _optype,
        starttime: _startStr,
        endtime: _endStr,
      );
      if (!mounted) return;

      if (result['success'] != true) {
        setState(() => _isLoadingMore = false);
        return;
      }

      setState(() {
        _items.addAll(_asItems(result['items']));
        _hasMore = result['hasMore'] == true;
        _page = nextPage;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      AppLogger.w('PAGE', 'CreditLogPage loadMore error: $e');
      setState(() => _isLoadingMore = false);
    }
  }

  /// 应用筛选并重新从第 1 页拉取
  void _applyFilters({String? exttype, String? income}) {
    setState(() {
      if (exttype != null) _exttype = exttype;
      if (income != null) _income = income;
    });
    _fetch();
  }

  void _clearOptype() {
    setState(() => _optype = '');
    _fetch();
  }

  /// 「详情」列链接 → App 路由落地：
  /// - `goto=findpost` 且缺 ptid：先按 pid 解析出 tid，补成带 ptid 的链接，
  ///   交给 UrlRouter → App 内帖子页（ThreadViewPage 会再据 pid 定位到楼层）
  /// - 其余：直接交给 UrlRouter（App 内页面优先，未知兜底内置浏览器）
  Future<void> _openDetailLink(String url) async {
    final target = await _detailTarget(url);
    if (target != null && mounted) context.push(target);
  }

  Future<String?> _detailTarget(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      final q = uri.queryParameters;
      final pid = q['pid'] ?? '';
      final hasPtid = (q['ptid'] ?? '').isNotEmpty;
      if (q['goto'] == 'findpost' && !hasPtid && pid.isNotEmpty) {
        final r = await viewpid_api.resolveTidByPid(ApiService().dio, pid: pid);
        final tid = r['success'] == true ? (r['tid'] as String? ?? '') : '';
        if (tid.isNotEmpty) {
          final withPtid = uri.replace(queryParameters: {...q, 'ptid': tid});
          return UrlRouter.resolveTarget(withPtid.toString());
        }
      }
    }
    return UrlRouter.resolveTarget(url);
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _start != null && _end != null
          ? DateTimeRange(start: _start!, end: _end!)
          : null,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _start = picked.start;
      _end = picked.end;
    });
    _fetch();
  }

  void _clearDateRange() {
    setState(() {
      _start = null;
      _end = null;
    });
    _fetch();
  }

  List<Map<String, dynamic>> _asItems(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('积分记录'),
        actions: [
          PageActions(
            url:
                '${SiteStore.instance.baseUrl}/home.php?mod=spacecp&ac=credit&op=log',
            onRefresh: _fetch,
            loading: _isLoading,
            copyLabel: '复制记录链接',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Divider(height: 1, color: cs.outlineVariant),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  // ==================== 筛选栏 ====================

  Widget _buildFilterBar() {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: [
          _filterRow('积分', [
            _choiceChip(
              '全部',
              _exttype == '0',
              () => _applyFilters(exttype: '0'),
            ),
            _choiceChip(
              '好评',
              _exttype == '1',
              () => _applyFilters(exttype: '1'),
            ),
            _choiceChip(
              '金币',
              _exttype == '2',
              () => _applyFilters(exttype: '2'),
            ),
            _choiceChip(
              '信誉',
              _exttype == '3',
              () => _applyFilters(exttype: '3'),
            ),
          ]),
          const SizedBox(height: 6),
          _filterRow('收支', [
            _choiceChip('全部', _income == '0', () => _applyFilters(income: '0')),
            _choiceChip('收入', _income == '1', () => _applyFilters(income: '1')),
            _choiceChip(
              '支出',
              _income == '-1',
              () => _applyFilters(income: '-1'),
            ),
            _dateChip(),
            if (_optype.isNotEmpty) _optypeChip(),
          ]),
        ],
      ),
    );
  }

  Widget _filterRow(String label, List<Widget> chips) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ),
        Expanded(child: Wrap(spacing: 6, runSpacing: 4, children: chips)),
      ],
    );
  }

  Widget _choiceChip(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelStyle: const TextStyle(fontSize: 12),
    );
  }

  Widget _dateChip() {
    final hasRange = _start != null && _end != null;
    final label = hasRange
        ? '${_shortDate(_start!)} ~ ${_shortDate(_end!)}'
        : '全部时间';
    return InputChip(
      avatar: const Icon(Icons.date_range, size: 15),
      label: Text(label),
      onPressed: _pickDateRange,
      onDeleted: hasRange ? _clearDateRange : null,
      deleteIcon: const Icon(Icons.close, size: 14),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelStyle: const TextStyle(fontSize: 12),
    );
  }

  static String _shortDate(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 「操作」筛选（由 URL/深链带入时显示，可移除）
  Widget _optypeChip() {
    return InputChip(
      avatar: const Icon(Icons.filter_alt_outlined, size: 15),
      label: const Text('操作筛选'),
      onDeleted: _clearOptype,
      deleteIcon: const Icon(Icons.close, size: 14),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelStyle: const TextStyle(fontSize: 12),
    );
  }

  // ==================== 列表 ====================

  Widget _buildList() {
    if (_isLoading) return const LoadingView();

    if (_error != null) {
      return PageErrorWidget(message: _error!, onRetry: _fetch);
    }

    if (_items.isEmpty) {
      return const EmptyView(
        icon: Icons.receipt_long_outlined,
        text: '没有符合条件的记录',
      );
    }

    // 宽屏按可用宽度自适应多列，避免一行一条浪费空间
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnsFor(constraints.maxWidth);
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollEndNotification) _onScroll();
            return false;
          },
          child: ListView.builder(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(8),
            itemCount: _items.length + (_isLoadingMore || !_hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= _items.length) {
                return LoadMoreFooter(
                  loading: _isLoadingMore,
                  hasMore: _hasMore,
                );
              }
              if (columns <= 1) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _buildCard(index),
                );
              }
              // 多列：按行分组，每列一个 Expanded（与收藏页同范式）
              if (index % columns != 0) return const SizedBox.shrink();
              final rowEnd = (index + columns).clamp(0, _items.length);
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (int i = index; i < rowEnd; i++) ...[
                      if (i > index) const SizedBox(width: 6),
                      Expanded(child: _buildCard(i)),
                    ],
                    if (rowEnd - index < columns)
                      ...List.generate(
                        columns - (rowEnd - index),
                        (_) => const Expanded(child: SizedBox.shrink()),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// 由可用宽度决定列数：窄屏 1 列，宽屏最多 4 列
  int _columnsFor(double width) {
    if (width >= 1100) return 4;
    if (width >= 820) return 3;
    if (width >= 560) return 2;
    return 1;
  }

  Widget _buildCard(int index) {
    final item = _items[index];
    final detailUrl = item['detailUrl'] as String? ?? '';
    return _CreditCard(
      item: item,
      // 详情 → URL 路由打开相关内容（帖子/道具/主题…）
      onDetailTap: detailUrl.isNotEmpty
          ? () => _openDetailLink(detailUrl)
          : null,
    );
  }
}

/// 单条积分记录卡片：操作 + 积分变更（增减着色）+ 详情 + 时间。
///
/// 「操作」为纯文字；「详情」在服务端带链接时可点（[onDetailTap]，经 URL 路由落地）。
class _CreditCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback? onDetailTap;

  const _CreditCard({required this.item, this.onDetailTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final action = item['action'] as String? ?? '';
    final creditType = item['creditType'] as String? ?? '';
    final delta = item['delta'] as String? ?? '';
    final detail = item['detail'] as String? ?? '';
    final time = item['time'] as String? ?? '';

    // 积分变更着色：增加用主题色、减少用错误色（数值本身带 +/- 号）
    final Color? deltaColor = delta.startsWith('+')
        ? cs.primary
        : delta.startsWith('-')
        ? cs.error
        : null;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    action,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$creditType $delta'.trim(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: deltaColor ?? cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 4),
              _linkable(
                context,
                text: detail,
                onTap: onDetailTap,
                trailingIcon: true,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ],
            if (time.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                time,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 可点文本：有链接时用主题色 + 下划线提示并处理点击，无链接时纯文本。
  Widget _linkable(
    BuildContext context, {
    required String text,
    required VoidCallback? onTap,
    required TextStyle style,
    bool trailingIcon = false,
  }) {
    if (onTap == null) return Text(text, style: style);
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Text(
              text,
              style: style.copyWith(
                color: cs.primary,
                decoration: TextDecoration.underline,
                decorationColor: cs.primary.withValues(alpha: 0.4),
              ),
            ),
          ),
          if (trailingIcon) ...[
            const SizedBox(width: 2),
            Icon(Icons.open_in_new, size: 12, color: cs.primary),
          ],
        ],
      ),
    );
  }
}
