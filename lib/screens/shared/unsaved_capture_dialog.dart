import 'package:flutter/material.dart';

import 'confirm_dialog.dart';

enum LeaveCaptureAction { continueCapturing, discard, saveAndLeave }

/// "You have unsaved burst photos" — shown whenever the user tries to
/// leave the camera (a bottom-nav tab, Android back) while a burst capture
/// session still has pending, uncommitted shots. Not shown for app
/// backgrounding (the Home button): nothing is lost in that case, since
/// every shot is already persisted, so there's nothing to confirm — see
/// `CaptureScreen`'s lifecycle handling.
Future<LeaveCaptureAction> showUnsavedCaptureDialog(
  BuildContext context, {
  required int count,
}) async {
  final result = await showDialog<LeaveCaptureAction>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Unsaved photos'),
      content: Text(
        'You have $count captured photo${count == 1 ? '' : 's'} that '
        "haven't been added to your collection yet.",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, LeaveCaptureAction.discard),
          child: const Text('Discard'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, LeaveCaptureAction.continueCapturing),
          child: const Text('Continue capturing'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, LeaveCaptureAction.saveAndLeave),
          child: const Text('Save & leave'),
        ),
      ],
    ),
  );
  // A dismissed dialog (outside tap / stray back) is treated the same as
  // an explicit "Continue capturing" — the safe, non-destructive default.
  return result ?? LeaveCaptureAction.continueCapturing;
}

/// Discard is destructive, so it gets its own confirmation on top of the
/// dialog above — reuses the app's existing Cancel/Delete dialog rather
/// than a bespoke one.
Future<bool> confirmDiscardCapture(BuildContext context, int count) {
  return confirmDelete(
    context,
    title: 'Discard $count captured photo${count == 1 ? '' : 's'}?',
    message:
        "These photos haven't been added to your collection. This cannot "
        'be undone.',
    confirmLabel: 'Discard',
  );
}

enum RecoverCaptureAction { discard, recover }

/// Shown once, shortly after app start, when a previous burst session was
/// left mid-capture — by a backgrounded app getting killed, a crash, or a
/// force-close — and still has photos sitting in it.
Future<RecoverCaptureAction> showRecoverCaptureDialog(
  BuildContext context, {
  required int count,
}) async {
  final result = await showDialog<RecoverCaptureAction>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Recover capture session?'),
      content: Text(
        '$count photo${count == 1 ? '' : 's'} from your previous capture '
        'session were recovered.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, RecoverCaptureAction.discard),
          child: const Text('Discard'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, RecoverCaptureAction.recover),
          child: const Text('Recover'),
        ),
      ],
    ),
  );
  // Barrier is non-dismissible and both actions return a value, so this
  // only matters for a stray system back — default to the non-destructive
  // choice, which keeps the photos safe either way.
  return result ?? RecoverCaptureAction.recover;
}
