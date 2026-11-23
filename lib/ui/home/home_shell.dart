import 'package:flutter/material.dart';

import '../common/layout.dart';
import '../common/strings.dart';
import '../notebooks/notebooks_screen.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';

/// 主界面骨架：底部导航（窄屏）/ 侧边栏（宽屏、桌面端）+ 三个一级页面。
///
/// 页面放在 [IndexedStack] 中常驻，切换标签不会丢失搜索词或列表滚动位置。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const List<_Destination> _destinations = [
    _Destination(
      icon: Icons.folder_outlined,
      selectedIcon: Icons.folder_rounded,
      label: S.tabNotebooks,
    ),
    _Destination(
      icon: Icons.search_rounded,
      selectedIcon: Icons.search_rounded,
      label: S.tabSearch,
    ),
    _Destination(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
      label: S.tabSettings,
    ),
  ];

  int _index = 0;

  void _select(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final body = IndexedStack(
      index: _index,
      children: const [
        NotebooksScreen(),
        SearchScreen(),
        SettingsScreen(),
      ],
    );

    // 宽屏（手机横屏、平板、桌面窗口）用侧边导航：更省竖向空间，也更符合桌面习惯。
    if (Responsive.useSideNavigation(context)) {
      return Scaffold(
        body: Row(
          children: [
            SafeArea(
              right: false,
              child: NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: _select,
                labelType: NavigationRailLabelType.all,
                leading: const _RailBrand(),
                destinations: [
                  for (final destination in _destinations)
                    NavigationRailDestination(
                      icon: Icon(destination.icon),
                      selectedIcon: Icon(destination.selectedIcon),
                      label: Text(destination.label),
                    ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: [
          for (final destination in _destinations)
            NavigationDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.selectedIcon),
              label: destination.label,
            ),
        ],
      ),
    );
  }
}

class _Destination {
  const _Destination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// 侧边栏顶部的品牌标记。
class _RailBrand extends StatelessWidget {
  const _RailBrand();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primary, scheme.tertiary],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.edit_note_rounded, size: 24, color: scheme.onPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            S.appName,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
