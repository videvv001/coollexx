import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/photo_store.dart';
import '../../models/capture_item.dart';
import '../../models/tcg_card.dart';
import '../../state/app_state.dart';
import '../shared/unsaved_capture_dialog.dart';
import 'batch_triage_screen.dart';
import 'camera_controller_mixin.dart';
import 'crop_retake_screen.dart';
import 'live_framing.dart';
import 'photo_preview_screen.dart';

enum CaptureMode { burst, guided }

/// The camera screen. `1a` (rapid burst) and `1c` (guided frame scan) are
/// built as two modes of this one screen, per the design README's own
/// recommendation for the safest reading of an undecided brief.
///
/// Burst shots are protected against navigation, app backgrounding, and
/// process death: each one is recorded in a persistent `CaptureSession` the
/// moment it's captured (see `_onBurstShutter`/`CaptureSessionRepository`),
/// not just held in this State's `_items` list. `resumeSessionId` reopens
/// an existing session — used when the app finds one left over from an
/// interrupted run (see `AppShell`'s startup recovery check) — rather than
/// starting a new one.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({
    super.key,
    this.boundReleaseId,
    this.boundSetSlotNumber,
    this.startAtUnsortedTray = false,
    this.resumeSessionId,
  });

  final String? boundReleaseId;
  final String? boundSetSlotNumber;
  final bool startAtUnsortedTray;
  final String? resumeSessionId;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with CameraControllerMixin, WidgetsBindingObserver {
  late CaptureMode _mode = widget.resumeSessionId != null
      ? CaptureMode.burst
      : widget.boundSetSlotNumber != null
      ? CaptureMode.guided
      : CaptureMode.burst;
  bool _burstContinuous = true;
  bool _autoShutter = true;
  FlashMode _flash = FlashMode.off;
  final String _side = 'Front';
  bool _gridOverlay = false;

  // Burst capture session (see class doc). `_items` mirrors what's already
  // durably persisted via `_sessionId` — never the other way around: a shot
  // is only appended here *after* `CaptureSessionRepository.addItem`
  // succeeds, per the project's "don't display a count you haven't
  // actually protected yet" requirement.
  String? _sessionId;
  final List<CaptureItem> _items = [];
  bool _committing = false;

  // Live framing: pinch-to-zoom uses real camera zoom (CameraControllerMixin
  // .setZoom), so the sensor itself — not just the preview widget — is
  // zoomed. The capture frame below is a *fixed* fraction of whatever the
  // camera currently sees (see `captureFrameFraction`), so it needs no
  // separate pan/position state: zoom handles magnification, the frame
  // handles trimming the preview's native aspect ratio down to a card's.
  // Both persist for the whole camera session and are only ever changed by
  // an explicit pinch or Reset tap — never reset between shots — which is
  // what lets burst capture reuse the same framing across many photos.
  double? _zoomGestureStart;
  bool _capturing = false;

  // Tap-to-focus: `_previewKey` is what turns a tap's local position into a
  // normalized (0-1) point for `setFocusPoint`/`setExposurePoint` — both
  // expect that coordinate space, not pixels. `_focusPoint` only exists to
  // draw the transient ring where the user tapped; it self-clears after a
  // beat rather than tracking whether focus actually locked (the camera
  // package doesn't expose that), so it's a tap acknowledgement, not a
  // focus-confirmed indicator.
  final _previewKey = GlobalKey();
  Offset? _focusPoint;

  void _onScaleStart(ScaleStartDetails details) {
    _zoomGestureStart = currentZoom;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final start = _zoomGestureStart;
    if (start == null) return;
    setZoom(start * details.scale);
  }

  Future<void> _onFocusTap(TapUpDetails details) async {
    final controller = cameraController;
    final box = _previewKey.currentContext?.findRenderObject() as RenderBox?;
    if (controller == null || box == null) return;
    final local = details.localPosition;
    final point = Offset(
      (local.dx / box.size.width).clamp(0.0, 1.0),
      (local.dy / box.size.height).clamp(0.0, 1.0),
    );
    setState(() => _focusPoint = local);
    try {
      await controller.setFocusMode(FocusMode.auto);
      await controller.setFocusPoint(point);
      await controller.setExposurePoint(point);
    } catch (_) {
      // Tap-to-focus/exposure isn't supported on this device — ignore.
    }
    await Future.delayed(const Duration(milliseconds: 700));
    if (mounted) setState(() => _focusPoint = null);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initCamera();
    _resumeIfNeeded();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    disposeCamera();
    super.dispose();
  }

  /// App backgrounding (Home, task switch, an incoming call) is *not*
  /// treated as "leaving the camera" — no confirmation, no discard. Every
  /// shot is already safely persisted, so the only thing to do is release
  /// the camera hardware while we're not visible and reacquire it on
  /// return. The capture session itself is untouched either way.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (cameraController != null) setState(disposeCamera);
    } else if (state == AppLifecycleState.resumed &&
        cameraController == null &&
        cameraError == null) {
      initCamera();
    }
  }

  Future<void> _resumeIfNeeded() async {
    final sessionId = widget.resumeSessionId;
    if (sessionId == null) return;
    final items = await context.read<AppState>().captureSessions.items(
      sessionId,
    );
    if (!mounted) return;
    setState(() {
      _sessionId = sessionId;
      _items.addAll(items);
    });
  }

  Future<void> _toggleFlash() async {
    final next = _flash == FlashMode.off ? FlashMode.torch : FlashMode.off;
    try {
      await cameraController?.setFlashMode(next);
    } catch (_) {
      // Flash not supported — ignore.
    }
    setState(() => _flash = next);
  }

  Future<XFile?> _takeShot() async {
    final controller = cameraController;
    if (controller == null || !controller.value.isInitialized) return null;
    try {
      return await controller.takePicture();
    } catch (_) {
      return null;
    }
  }

  /// Takes a shot and crops it to the same region the live capture frame
  /// showed at the moment of capture (see `live_framing.dart`) — zoom is
  /// already baked in by the camera itself, this just trims the preview's
  /// native aspect ratio down to a card's. Guarded by `_capturing` so a
  /// second tap can't start an overlapping native capture; the crop itself
  /// runs off-thread, so this is normally sub-second.
  Future<String?> _captureFramed() async {
    if (_capturing) return null;
    setState(() => _capturing = true);
    try {
      final file = await _takeShot();
      if (file == null) return null;
      return await cropToFraming(file.path, kCardAspect);
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  /// Captures a shot and — this is the fix for the data-loss this screen
  /// used to be exposed to — immediately records it in the persistent
  /// capture session *before* it's ever reflected in the on-screen count.
  /// A session is created lazily on the very first successful shot rather
  /// than when the screen opens, so backing out of an empty burst never
  /// leaves a stray empty session behind.
  Future<void> _onBurstShutter() async {
    final path = await _captureFramed();
    if (path == null || !mounted) return;
    final state = context.read<AppState>();
    try {
      var sessionId = _sessionId;
      if (sessionId == null) {
        final session = await state.captureSessions.createSession(
          targetReleaseId: widget.boundReleaseId,
        );
        sessionId = session.id;
      }
      final item = await state.captureSessions.addItem(sessionId, path);
      if (!mounted) return;
      setState(() {
        _sessionId = sessionId;
        _items.add(item);
      });
      state.setPendingCapture(
        PendingCapture(sessionId: sessionId, count: _items.length),
      );
    } catch (_) {
      // The photo file itself is fine (already written above) but couldn't
      // be recorded in the session, so it can never be found again — clean
      // it up rather than leaving an orphaned file, and don't count it:
      // every previous capture stays exactly as it was.
      await PhotoStore.instance.delete(path);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text("Couldn't save that photo — try again")),
        );
    }
  }

  /// Turns every pending item into a real collection entry (see
  /// `CaptureSessionRepository.commit`) and clears the local session state.
  /// Shared by "Done · review" and "Save & leave" — the only difference is
  /// what the caller does with the result afterward.
  Future<List<TcgCard>> _commitSession() async {
    final sessionId = _sessionId;
    if (sessionId == null) return const [];
    final state = context.read<AppState>();
    setState(() => _committing = true);
    final cards = await state.captureSessions.commit(
      state.collection,
      sessionId,
    );
    await state.refresh();
    if (!mounted) return cards;
    state.setPendingCapture(null);
    setState(() {
      _committing = false;
      _sessionId = null;
      _items.clear();
    });
    return cards;
  }

  Future<void> _reviewBurst() async {
    final cards = await _commitSession();
    if (!mounted || cards.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BatchTriageScreen(
          cardIds: cards.map((c) => c.id).toList(),
          boundReleaseId: widget.boundReleaseId,
        ),
      ),
    );
  }

  /// The interception point for "leaving the camera with unsaved photos" —
  /// Android back and the close (X) button both route through this via
  /// `PopScope`/`Navigator.maybePop`. Not used for app backgrounding; see
  /// `didChangeAppLifecycleState`.
  Future<bool> _resolveLeaveConfirmation() async {
    final count = _items.length;
    final action = await showUnsavedCaptureDialog(context, count: count);
    if (!mounted) return false;
    switch (action) {
      case LeaveCaptureAction.continueCapturing:
        return false;
      case LeaveCaptureAction.discard:
        final confirmed = await confirmDiscardCapture(context, count);
        if (!confirmed || !mounted) return false;
        final state = context.read<AppState>();
        await state.captureSessions.discard(_sessionId!);
        state.setPendingCapture(null);
        setState(() {
          _sessionId = null;
          _items.clear();
        });
        return true;
      case LeaveCaptureAction.saveAndLeave:
        await _commitSession();
        return true;
    }
  }

  Future<void> _onGuidedShutter() async {
    final path = await _captureFramed();
    if (path == null || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CropRetakeScreen(
          photoPath: path,
          side: _side,
          boundReleaseId: widget.boundReleaseId,
          boundSetSlotNumber: widget.boundSetSlotNumber,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.startAtUnsortedTray) {
      return BatchTriageScreen(
        cardIds: const [],
        boundReleaseId: widget.boundReleaseId,
        useUnsortedTray: true,
      );
    }

    // This screen can stay mounted-but-hidden behind the bottom nav bar's
    // IndexedStack after the user switches tabs, and AppShell resolves an
    // "unsaved photos" prompt entirely through AppState/the repository
    // (see AppShell._resolvePendingCapture) without reaching into this
    // widget. `watch` here is what notices that happened — on the next
    // build, our local session no longer matches AppState's — so a shot
    // taken after switching back doesn't try to save into an already
    // committed/discarded session.
    final pendingCapture = context.watch<AppState>().pendingCapture;
    if (_sessionId != null && pendingCapture?.sessionId != _sessionId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _sessionId = null;
          _items.clear();
        });
      });
    }

    return PopScope(
      // Blocks both the system back gesture/button *and* an imperative
      // Navigator.pop aimed at this route (see AppShell's own root
      // PopScope, which pops the active tab's nested Navigator on back —
      // this is what actually intercepts that). `Navigator.maybePop` below
      // routes the close button through the exact same check.
      canPop: _items.isEmpty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final proceed = await _resolveLeaveConfirmation();
        if (!proceed || !mounted) return;
        navigator.pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.maybePop(context),
                    ),
                    const Spacer(),
                    SegmentedButton<CaptureMode>(
                      segments: const [
                        ButtonSegment(
                          value: CaptureMode.burst,
                          label: Text('Quick burst'),
                        ),
                        ButtonSegment(
                          value: CaptureMode.guided,
                          label: Text('Guided scan'),
                        ),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (s) =>
                          setState(() => _mode = s.first),
                    ),
                    const Spacer(),
                    if (_mode == CaptureMode.burst)
                      IconButton(
                        icon: Icon(
                          _flash == FlashMode.off
                              ? Icons.flash_off
                              : Icons.flash_on,
                          color: Colors.white,
                        ),
                        onPressed: _toggleFlash,
                      )
                    else
                      const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: cameraError != null
                    ? _CameraUnavailable(message: cameraError!)
                    : !cameraReady
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : Center(
                        // A bounded AspectRatio here — matching the camera's own
                        // native ratio — so the inner Stack.expand sizes the
                        // preview to that box instead of stretching it to fill
                        // whatever space is left in the Column, which distorts it.
                        child: AspectRatio(
                          aspectRatio: 1 / cameraController!.value.aspectRatio,
                          child: GestureDetector(
                            key: _previewKey,
                            onScaleStart: _onScaleStart,
                            onScaleUpdate: _onScaleUpdate,
                            onTapUp: _onFocusTap,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                CameraPreview(cameraController!),
                                if (_gridOverlay) const _GridOverlay(),
                                _mode == CaptureMode.burst
                                    ? _CardGuide(
                                        hint: 'Keep shooting',
                                        frame: captureFrameFraction(
                                          previewAspect:
                                              1 /
                                              cameraController!
                                                  .value
                                                  .aspectRatio,
                                          targetAspect: kCardAspect,
                                        ),
                                      )
                                    : _GuidedGuide(
                                        auto: _autoShutter,
                                        frame: captureFrameFraction(
                                          previewAspect:
                                              1 /
                                              cameraController!
                                                  .value
                                                  .aspectRatio,
                                          targetAspect: kCardAspect,
                                        ),
                                      ),
                                _ZoomBadge(
                                  zoom: currentZoom,
                                  showReset: currentZoom > minZoomLevel + 0.01,
                                  onReset: resetZoom,
                                ),
                                if (_focusPoint != null)
                                  Positioned(
                                    left: _focusPoint!.dx - 32,
                                    top: _focusPoint!.dy - 32,
                                    child: const _FocusRing(),
                                  ),
                                if (_capturing)
                                  const ColoredBox(
                                    color: Colors.black26,
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
              if (_mode == CaptureMode.burst)
                _BurstControls(
                  continuous: _burstContinuous,
                  onModeChanged: (v) => setState(() => _burstContinuous = v),
                  shotCount: _items.length,
                  committing: _committing,
                  onShutter: _committing ? null : _onBurstShutter,
                  onReview: _items.isEmpty || _committing ? null : _reviewBurst,
                  recentPaths: _items.reversed
                      .map((i) => i.path)
                      .take(6)
                      .toList(),
                  onPathEdited: (oldPath, newPath) async {
                    final index = _items.indexWhere((i) => i.path == oldPath);
                    if (index == -1) return;
                    final item = _items[index];
                    await context
                        .read<AppState>()
                        .captureSessions
                        .updateItemPath(item, newPath);
                    if (!mounted) return;
                    setState(
                      () => _items[index] = item.copyWith(path: newPath),
                    );
                  },
                )
              else
                _GuidedControls(
                  auto: _autoShutter,
                  onModeChanged: (v) => setState(() => _autoShutter = v),
                  side: _side,
                  gridOn: _gridOverlay,
                  onToggleGrid: () =>
                      setState(() => _gridOverlay = !_gridOverlay),
                  onShutter: _onGuidedShutter,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              color: Colors.white54,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// The live capture frame: a corner-bracket outline sized to exactly the
/// [frame] fraction of the preview that `cropToFraming` keeps, so what's
/// inside the brackets is what ends up in the saved photo. Centered via
/// `Center` + `FractionallySizedBox` against the *whole* preview stack
/// (not a nested aspect-ratio box), so `frame`'s width/height factors are
/// exactly the crop fractions computed in `live_framing.dart`.
class _CardGuide extends StatelessWidget {
  const _CardGuide({required this.hint, required this.frame});

  final String hint;
  final ({double width, double height}) frame;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: FractionallySizedBox(
            widthFactor: frame.width,
            heightFactor: frame.height,
            child: CustomPaint(painter: _CornerBracketsPainter()),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 16,
          child: Center(child: _HintChip(hint)),
        ),
      ],
    );
  }
}

class _HintChip extends StatelessWidget {
  const _HintChip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white)),
    );
  }
}

/// Zoom readout + optional Reset, overlaid top-right of the preview. Shows
/// native camera zoom (`CameraControllerMixin.currentZoom`) — the same
/// value that's actually applied to the sensor, not a preview-only scale.
class _ZoomBadge extends StatelessWidget {
  const _ZoomBadge({
    required this.zoom,
    required this.showReset,
    required this.onReset,
  });

  final double zoom;
  final bool showReset;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${zoom.toStringAsFixed(1)}×',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            if (showReset) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onReset,
                child: const Icon(Icons.refresh, color: Colors.white, size: 16),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Transient ring drawn where the user tapped to focus — a tap
/// acknowledgement, not confirmation that focus actually locked (the
/// `camera` package doesn't report that back).
class _FocusRing extends StatelessWidget {
  const _FocusRing();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.3, end: 1.0),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
      ),
    );
  }
}

class _CornerBracketsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    const len = 24.0;
    final rect = Offset.zero & size;
    for (final corner in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      final dx = corner.dx == rect.left ? 1.0 : -1.0;
      final dy = corner.dy == rect.top ? 1.0 : -1.0;
      canvas.drawLine(corner, corner + Offset(dx * len, 0), paint);
      canvas.drawLine(corner, corner + Offset(0, dy * len), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GuidedGuide extends StatefulWidget {
  const _GuidedGuide({required this.auto, required this.frame});

  final bool auto;
  final ({double width, double height}) frame;

  @override
  State<_GuidedGuide> createState() => _GuidedGuideState();
}

class _GuidedGuideState extends State<_GuidedGuide> {
  String _status = 'Positioning…';

  @override
  void initState() {
    super.initState();
    if (widget.auto) _runCountdown();
  }

  @override
  void didUpdateWidget(covariant _GuidedGuide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.auto && !oldWidget.auto) _runCountdown();
    if (!widget.auto) setState(() => _status = 'Manual — tap shutter');
  }

  Future<void> _runCountdown() async {
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted || !widget.auto) return;
    setState(() => _status = '4 edges locked');
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted || !widget.auto) return;
    setState(() => _status = 'Shooting in 1…');
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: FractionallySizedBox(
            widthFactor: widget.frame.width,
            heightFactor: widget.frame.height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.white38,
                      width: 1,
                      style: BorderStyle.solid,
                    ),
                  ),
                ),
                Center(
                  child: FractionallySizedBox(
                    widthFactor: 0.94,
                    heightFactor: 0.94,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ),
                const Center(
                  child: Icon(Icons.add, color: Colors.white38, size: 18),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 16,
          child: Center(child: _HintChip(_status)),
        ),
      ],
    );
  }
}

class _GridOverlay extends StatelessWidget {
  const _GridOverlay();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _GridPainter(), size: Size.infinite);
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = size.width / 3 * i;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      final y = size.height / 3 * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BurstControls extends StatelessWidget {
  const _BurstControls({
    required this.continuous,
    required this.onModeChanged,
    required this.shotCount,
    required this.committing,
    required this.onShutter,
    required this.onReview,
    required this.recentPaths,
    required this.onPathEdited,
  });

  final bool continuous;
  final ValueChanged<bool> onModeChanged;
  final int shotCount;
  final bool committing;
  final VoidCallback? onShutter;
  final VoidCallback? onReview;
  final List<String> recentPaths;
  final void Function(String oldPath, String newPath) onPathEdited;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Burst')),
              ButtonSegment(value: false, label: Text('Single')),
            ],
            selected: {continuous},
            onSelectionChanged: (s) => onModeChanged(s.first),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 96,
                child: recentPaths.isEmpty
                    ? Text(
                        '$shotCount shot',
                        style: const TextStyle(color: Colors.white70),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 40,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                for (final path in recentPaths)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: GestureDetector(
                                      onTap: () async {
                                        final edited =
                                            await Navigator.push<String>(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    PhotoPreviewScreen(
                                                      path: path,
                                                    ),
                                              ),
                                            );
                                        if (edited != null) {
                                          onPathEdited(path, edited);
                                        }
                                      },
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: Image.file(
                                          File(path),
                                          width: 32,
                                          height: 40,
                                          fit: BoxFit.cover,
                                          cacheWidth: 64,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          // "Draft saved", never "Saved" alone — these
                          // shots are durably persisted but not yet part
                          // of the collection, and the wording shouldn't
                          // let that read as already committed.
                          Text(
                            '$shotCount captured · Draft saved',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
              ),
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onTap: onShutter,
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: onShutter == null
                            ? Colors.white38
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 96,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: onReview,
                    child: committing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text('Done · review $shotCount'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GuidedControls extends StatelessWidget {
  const _GuidedControls({
    required this.auto,
    required this.onModeChanged,
    required this.side,
    required this.gridOn,
    required this.onToggleGrid,
    required this.onShutter,
  });

  final bool auto;
  final ValueChanged<bool> onModeChanged;
  final String side;
  final bool gridOn;
  final VoidCallback onToggleGrid;
  final VoidCallback onShutter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Auto')),
              ButtonSegment(value: false, label: Text('Manual')),
            ],
            selected: {auto},
            onSelectionChanged: (s) => onModeChanged(s.first),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Text(side, style: const TextStyle(color: Colors.white70)),
              TextButton.icon(
                onPressed: onToggleGrid,
                icon: Icon(
                  Icons.grid_on,
                  color: gridOn ? Colors.white : Colors.white38,
                ),
                label: Text(
                  'Grid',
                  style: TextStyle(
                    color: gridOn ? Colors.white : Colors.white38,
                  ),
                ),
              ),
              const Text('Level', style: TextStyle(color: Colors.white38)),
              const Text('Glare', style: TextStyle(color: Colors.white38)),
            ],
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onShutter,
            child: Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
