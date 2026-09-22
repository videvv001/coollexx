import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/capture_session.dart';
import 'screens/capture/capture_route.dart';
import 'screens/capture/capture_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/me/me_screen.dart';
import 'screens/sets/sets_screen.dart';
import 'screens/shared/unsaved_capture_dialog.dart';
import 'screens/trade/trade_screen.dart';
import 'state/app_state.dart';

/// The collection shell: a persistent 4-tab bar (Collection · Sets · Trade ·
/// Me — the `2a` reading from the design brief, where Value lives on the
/// card detail rather than getting its own tab) with each tab keeping its
/// own navigation stack so drilling into a folder or a card doesn't lose
/// the other tabs' place.
///
/// Also the two places a burst capture session gets protected from outside
/// the camera screen itself: switching tabs while one has unsaved photos
/// (`onDestinationSelected` below) prompts the same as the camera's own
/// back-button confirmation, and a leftover session found at app start
/// (`_checkForRecoverableCapture`) offers to recover or discard it.
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkForRecoverableCapture(),
    );
  }

  /// Runs once, shortly after launch. A capture-session row surviving to
  /// this point means the app never got to finish with it last time —
  /// backgrounded and killed, crashed, or force-closed — since a normal
  /// commit or discard always deletes its own row when it finishes.
  Future<void> _checkForRecoverableCapture() async {
    final appState = context.read<AppState>();
    final repo = appState.captureSessions;
    final active = await repo.activeSession();
    if (active == null || !mounted) return;

    if (active.status == CaptureSessionStatus.committing) {
      // The app died partway through committing, after the user already
      // asked to save — finish that quietly rather than asking again.
      // `commit` is idempotent, so this can't duplicate whatever part of
      // it already succeeded.
      await repo.commit(appState.collection, active.id);
      await appState.refresh();
      return;
    }

    final count = await repo.itemCount(active.id);
    if (count == 0) {
      // A session row with no items — e.g. created but the app died before
      // the first shot's own insert completed. Nothing to recover.
      await repo.discard(active.id);
      return;
    }
    if (!mounted) return;

    final action = await showRecoverCaptureDialog(context, count: count);
    if (!mounted) return;
    if (action == RecoverCaptureAction.discard) {
      final confirmed = await confirmDiscardCapture(context, count);
      if (confirmed) await repo.discard(active.id);
      return;
    }

    appState.setPendingCapture(
      PendingCapture(sessionId: active.id, count: count),
    );
    setState(() {
      _index = 0;
      _visited.add(0);
    });
    _navigatorKeys[0].currentState?.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: captureRouteName),
        builder: (_) => CaptureScreen(
          resumeSessionId: active.id,
          boundReleaseId: active.targetReleaseId,
        ),
      ),
    );
  }

  /// Returns true once it's safe to switch tabs — either nothing was
  /// pending, or the user explicitly chose to save or discard it.
  Future<bool> _resolvePendingCapture() async {
    final appState = context.read<AppState>();
    final pending = appState.pendingCapture;
    if (pending == null) return true;
    final action = await showUnsavedCaptureDialog(
      context,
      count: pending.count,
    );
    if (!mounted) return false;
    switch (action) {
      case LeaveCaptureAction.continueCapturing:
        return false;
      case LeaveCaptureAction.discard:
        final confirmed = await confirmDiscardCapture(context, pending.count);
        if (!confirmed || !mounted) return false;
        await appState.captureSessions.discard(pending.sessionId);
        appState.setPendingCapture(null);
        return true;
      case LeaveCaptureAction.saveAndLeave:
        await appState.captureSessions.commit(
          appState.collection,
          pending.sessionId,
        );
        await appState.refresh();
        if (!mounted) return false;
        appState.setPendingCapture(null);
        return true;
    }
  }

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
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: 0.5,
              ),
            ),
          ),
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) async {
              if (i == _index) {
                _navigatorKeys[i].currentState?.popUntil((r) => r.isFirst);
                return;
              }
              if (!await _resolvePendingCapture()) return;
              setState(() {
                _index = i;
                _visited.add(i);
              });
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
      ),
    );
  }
}
