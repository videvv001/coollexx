// Regression coverage for the Edit Folder cover-picker layering bug: the
// picker's bottom sheet must render *above* a dialog even when the sheet is
// opened with a BuildContext from a tab's own nested Navigator (AppShell
// gives each bottom tab its own Navigator) rather than the dialog's own
// inner context. `showDialog` defaults to `useRootNavigator: true`;
// `showModalBottomSheet` defaults to `useRootNavigator: false` — without
// forcing the sheet onto the root Navigator too, it lands on a different,
// lower Overlay layer than the dialog and gets hidden behind it. This test
// reproduces AppShell's nested-Navigator shape directly rather than booting
// the full app, since the full app boot hits an unrelated, pre-existing
// shared_preferences plugin-mock gap in this project's test harness
// (ThemeController; see widget_test.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'bottom sheet opened with a tab context still renders above a dialog',
    (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Navigator(
            onGenerateRoute: (settings) => MaterialPageRoute(
              builder: (tabContext) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: tabContext,
                    useRootNavigator: true,
                    builder: (dialogContext) => AlertDialog(
                      content: ElevatedButton(
                        // Mirrors `pickCover` in home_screen.dart: the
                        // callback closes over the outer tab context
                        // captured before showDialog ran, not the dialog's
                        // own builder context.
                        onPressed: () => showModalBottomSheet<void>(
                          context: tabContext,
                          useRootNavigator: true,
                          builder: (_) => ElevatedButton(
                            onPressed: () => tapped = true,
                            child: const Text('Choose from gallery'),
                          ),
                        ),
                        child: const Text('Edit cover'),
                      ),
                    ),
                  ),
                  child: const Text('Open Edit Folder'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Edit Folder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit cover'));
      await tester.pumpAndSettle();

      // If the sheet rendered behind the dialog, this tap would hit the
      // dialog's own modal barrier instead of the sheet's button.
      await tester.tap(find.text('Choose from gallery'));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    },
  );
}
