import 'package:flutter/material.dart';

/// Shared route name so screens deep in the capture flow (batch triage,
/// assign-to-release, name/tag/file) can pop back out of it — without each
/// one importing capture_screen.dart and creating an import cycle.
///
/// It names the route the flow was *entered* on, which is usually the
/// camera screen but not always: the Home unsorted tray, a folder's
/// gallery upload and the Home multi-pick all drop straight into triage or
/// name/tag/file with no camera behind them.
const captureRouteName = '/capture';

/// Pops back to the route the capture flow was entered on, and past it
/// too when [exit] is true (i.e. all the way back to whatever launched
/// capture).
///
/// The `isFirst` half of the predicate is not belt-and-braces: a flow
/// entered from a push that forgot [captureRouteName] has no such route on
/// the stack at all, and `popUntil` then empties the tab's navigator and
/// leaves a black screen.
void popCaptureFlow(BuildContext context, {required bool exit}) {
  final navigator = Navigator.of(context);
  var onEntry = false;
  navigator.popUntil((route) {
    onEntry = route.settings.name == captureRouteName;
    return onEntry || route.isFirst;
  });
  if (exit && onEntry) navigator.pop();
}
