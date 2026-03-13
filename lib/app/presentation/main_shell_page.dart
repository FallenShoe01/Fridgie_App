import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MainShellPage extends StatelessWidget {
  const MainShellPage({
    super.key,
    required this.child,
  });

  final Widget child;

  static const List<String> _tabRoots = <String>[
    '/main',
    '/products',
    '/catalog',
    '/settings',
  ];

  int _indexFromLocation(String location) {
    if (location.startsWith('/products')) return 1;
    if (location.startsWith('/catalog')) return 2;
    if (location.startsWith('/settings')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final String location = GoRouterState.of(context).uri.toString();
    final int selectedIndex = _indexFromLocation(location);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        destinations: <NavigationDestination>[
          NavigationDestination(
            icon: const Icon(Icons.dashboard_outlined),
            selectedIcon: const Icon(Icons.dashboard),
            label: 'nav_main'.tr(),
          ),
          NavigationDestination(
            icon: const Icon(Icons.inventory_2_outlined),
            selectedIcon: const Icon(Icons.inventory_2),
            label: 'nav_products'.tr(),
          ),
          NavigationDestination(
            icon: const Icon(Icons.bookmarks_outlined),
            selectedIcon: const Icon(Icons.bookmarks),
            label: 'nav_catalog'.tr(),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: 'nav_settings'.tr(),
          ),
        ],
        onDestinationSelected: (int index) {
          if (index == selectedIndex) {
            return;
          }
          context.go(_tabRoots[index]);
        },
      ),
    );
  }
}
