import 'package:flutter/material.dart';
import '../api/forum/rss/export.dart' as rss_api;
import '../services/api_service.dart';
import 'rss_tile.dart';

/// RSS 订阅区块
///
/// 自带数据加载和错误处理。
/// 父页面通过更改 key 触发重新加载。
class RssSection extends StatefulWidget {
  const RssSection({super.key});

  @override
  State<RssSection> createState() => _RssSectionState();
}

class _RssSectionState extends State<RssSection> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  String? _error;
  bool _everLoaded = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(covariant RssSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // key 改变时（父页面主动触发刷新），重新加载
    if (widget.key != oldWidget.key) {
      _everLoaded = false;
      _fetch();
    }
  }

  Future<void> _fetch() async {
    if (_everLoaded) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await rss_api.getRssFeed(ApiService().dio);
      if (!mounted) return;
      if (result['success'] == true) {
        _everLoaded = true;
        setState(() {
          _items = List<Map<String, dynamic>>.from(result['items'] ?? []);
          _loading = false;
        });
      } else {
        setState(() {
          _error = result['message']?.toString() ?? '获取 RSS 失败';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Text(
                'RSS 订阅',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
              const Spacer(),
              if (_items.isNotEmpty)
                Text(
                  '${_items.length} 条',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
            ],
          ),
        ),
        // 内容
        if (_loading && _items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_error != null && _items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.rss_feed, size: 40, color: Colors.grey.shade300),
                  const SizedBox(height: 8),
                  Text('加载失败', style: TextStyle(color: Colors.grey.shade500)),
                  Text(
                    _error!,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else if (_items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                '暂无帖子',
                style: TextStyle(color: Colors.grey.shade400),
              ),
            ),
          )
        else
          _buildRssList(),
      ],
    );
  }

  Widget _buildRssList() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;
        final tiles = _items.map((item) => RssTile(item: item)).toList();
        if (isWide) {
          return Wrap(
            spacing: 8,
            runSpacing: 0,
            children: tiles
                .map(
                  (t) =>
                      SizedBox(width: (constraints.maxWidth - 8) / 2, child: t),
                )
                .toList(),
          );
        }
        return Column(children: tiles);
      },
    );
  }
}
