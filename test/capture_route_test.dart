import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pokedex_tcg/screens/capture/capture_route.dart';

/// The bug this guards: flows entered outside the camera (Home's unsorted
/// tray, a folder's gallery upload) have no [captureRouteName] route on the
/// stack, and a name-only `popUntil` emptied the navigator — a black screen.
void main() {
  Widget page(String label) => Scaffold(body: Text(label));

  Future<void> pump(
    WidgetTester tester,
    List<String?> pushed, {
    required bool exit,
  }) async {
    late BuildContext top;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            top = context;
            return page('root');
          },
        ),
      ),
    );
    for (final name in pushed) {
      Navigator.push(
        top,
        MaterialPageRoute(
          settings: RouteSettings(name: name),
          builder: (context) {
            top = context;
            return page(name ?? 'unnamed');
          },
        ),
      );
      await tester.pumpAndSettle();
    }
    popCaptureFlow(top, exit: exit);
    await tester.pumpAndSettle();
  }

  testWidgets('no entry route on the stack still leaves the root showing', (
    tester,
  ) async {
    await pump(tester, [null, null], exit: true);
    expect(find.text('root'), findsOneWidget);
  });

  testWidgets('exit pops past the entry route', (tester) async {
    await pump(tester, [captureRouteName, null], exit: true);
    expect(find.text('root'), findsOneWidget);
  });

  testWidgets('without exit it lands on the entry route', (tester) async {
    await pump(tester, [captureRouteName, null, null], exit: false);
    expect(find.text(captureRouteName), findsOneWidget);
  });
}
