import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';

class MainShell extends StatelessWidget {
  const MainShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1, thickness: 1, color: AppColors.grayLight),
          Material(
            color: AppColors.white,
            elevation: 0,
            shadowColor: Colors.transparent,
            child: BottomNavigationBar(
              currentIndex: navigationShell.currentIndex,
              onTap: _onTap,
              type: BottomNavigationBarType.fixed,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.chat_bubble_outline),
                  activeIcon: Icon(Icons.chat_bubble),
                  label: '聊天',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.apps_outlined),
                  activeIcon: Icon(Icons.apps),
                  label: '应用',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.dashboard_outlined),
                  activeIcon: Icon(Icons.dashboard),
                  label: '工作台',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline),
                  activeIcon: Icon(Icons.person),
                  label: '我的',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
