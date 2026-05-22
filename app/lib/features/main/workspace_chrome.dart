import 'package:flutter/material.dart';

/// 工作台统一顶栏：标题、操作按钮、应用抽屉等。
class WorkspaceChrome {
  const WorkspaceChrome({
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.drawer,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? drawer;
}
