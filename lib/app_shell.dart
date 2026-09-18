import 'package:flutter/material.dart';

import 'screens/home/home_screen.dart';
import 'screens/me/me_screen.dart';
import 'screens/sets/sets_screen.dart';
import 'screens/trade/trade_screen.dart';

/// The collection shell: a persistent 4-tab bar (Collection · Sets · Trade ·
/// Me — the `2a` reading from the design brief, where Value lives on the
/// card detail rather than getting its own tab) with each tab keeping its
/// own navigation stack so drilling into a folder or a card doesn't lose
/// the other tabs' place.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  final Set<int> _visited = {0};
  final List<GlobalKey<NavigatorState>> _navigatorKeys = List.generate(
    4,
    (_) => GlobalKey<NavigatorState>(),
  );

  static const _tabs = [
    (
      label: 'Collection',
      icon: Icons.style_outlined,
      selectedIcon: Icons.style,
    ),
    (
      label: 'Sets',
      icon: Icons.grid_view_outlined,
      selectedIcon: Icons.grid_view,
    ),
    (
      label: 'Trade',
      icon: Icons.swap_horiz_outlined,
      selectedIcon: Icons.swap_horiz,
    ),
    (label: 'Me', icon: Icons.person_outline, selectedIcon: Icons.person),
  ];

  Widget _rootFor(int index) {
    switch (index) {
      case 0:
        return const HomeScreen();
      case 1:
        return const SetsScreen();
      case 2:
        return const TradeScreen();
      default:
        return const MeScreen();
    }
  }

  Widget _buildTabNavigator(int index) {
    // Unvisited tabs stay unmounted rather than building (and querying the
    // database from) all four up front — only the tabs the user actually
    // opens do any work.
    if (!_visited.contains(index)) return const SizedBox.shrink();
    return Navigator(
      key: _navigatorKeys[index],
      onGenerateRoute: (settings) => MaterialPageRoute(
        builder: (_) => _rootFor(index),
        settings: settings,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final nav = _navigatorKeys[_index].currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
        } else if (_index != 0) {
          setState(() => _index = 0);
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: List.generate(4, _buildTabNavigator),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) {
            if (i == _index) {
              _navigatorKeys[i].currentState?.popUntil((r) => r.isFirst);
            } else {
              setState(() {
                _index = i;
                _visited.add(i);
              });
            }
          },
          destinations: [
            for (final tab in _tabs)
              NavigationDestination(
                icon: Icon(tab.icon),
                selectedIcon: Icon(tab.selectedIcon),
                label: tab.label,
              ),
          ],
        ),
      ),
    );
  }
}
