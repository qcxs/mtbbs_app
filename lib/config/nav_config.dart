import 'package:flutter/material.dart';

/// 导航 Tab 配置项
class NavItem {
  final String label;
  final IconData icon;
  final IconData iconFilled;
  final String path;
  const NavItem(this.label, this.icon, this.iconFilled, this.path);
}

/// 导航栏 Tab 列表（同一数据源驱动底栏、侧栏和默认启动页设置）
const navItems = [
  NavItem('首页', Icons.home_outlined, Icons.home, '/'),
  NavItem('导读', Icons.explore_outlined, Icons.explore, '/guide'),
  NavItem('社区', Icons.forum_outlined, Icons.forum, '/community'),
  NavItem('我的', Icons.person_outline, Icons.person, '/profile'),
];
