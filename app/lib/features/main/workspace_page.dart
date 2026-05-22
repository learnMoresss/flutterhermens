import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import 'workspace_chrome.dart';
import '../docker/docker_page.dart';
import '../hermes_console/hermes_console_page.dart';

/// 工作台：运维 / Docker，应用已独立为底部导航 Tab。
class WorkspacePage extends StatefulWidget {
  const WorkspacePage({super.key});

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  int _tab = 0;

  static const _tabs = [
    (label: '运维', icon: Icons.tune_outlined, activeIcon: Icons.tune),
    (label: 'Docker', icon: Icons.view_in_ar_outlined, activeIcon: Icons.view_in_ar),
  ];

  static const _defaultChrome = [
    WorkspaceChrome(title: 'Hermes 运维', subtitle: '备份、Agent 与 Gateway 管理'),
    WorkspaceChrome(title: 'Docker', subtitle: '容器与服务状态'),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tabRaw = GoRouterState.of(context).uri.queryParameters['tab'];
    if (tabRaw == null) return;
    final idx = int.tryParse(tabRaw);
    if (idx == null || idx < 0 || idx >= _tabs.length || idx == _tab) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _tab = idx);
    });
  }

  @override
  Widget build(BuildContext context) {
    final chrome = _defaultChrome[_tab];

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        toolbarHeight: 52,
        titleSpacing: 0,
        automaticallyImplyLeading: false,
        title: _HeaderTitle(title: chrome.title, subtitle: chrome.subtitle),
        actions: chrome.actions,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: _WorkspaceTabStrip(
                  tabs: _tabs,
                  index: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                ),
              ),
              const Divider(height: 1, thickness: 1, color: AppColors.grayLight),
            ],
          ),
        ),
      ),
      body: IndexedStack(
        index: _tab,
        children: const [
          HermesConsolePage(embedded: true),
          DockerPage(embedded: true),
        ],
      ),
    );
  }
}

class _HeaderTitle extends StatelessWidget {
  const _HeaderTitle({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.black,
              height: 1.2,
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty)
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.gray,
                height: 1.2,
              ),
            ),
        ],
      ),
    );
  }
}

class _WorkspaceTabStrip extends StatelessWidget {
  const _WorkspaceTabStrip({
    required this.tabs,
    required this.index,
    required this.onChanged,
  });

  final List<({String label, IconData icon, IconData activeIcon})> tabs;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.grayLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              Expanded(
                child: _TabPill(
                  label: tabs[i].label,
                  icon: tabs[i].icon,
                  activeIcon: tabs[i].activeIcon,
                  selected: index == i,
                  onTap: () => onChanged(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.black : Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? activeIcon : icon,
                size: 16,
                color: selected ? AppColors.white : AppColors.gray,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? AppColors.white : AppColors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
