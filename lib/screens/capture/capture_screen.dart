import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'batch_triage_screen.dart';
import 'camera_controller_mixin.dart';
import 'capture_route.dart';
import 'crop_retake_screen.dart';
import 'photo_preview_screen.dart';

enum CaptureMode { burst, guided }

/// The camera screen. `1a` (rapid burst) and `1c` (guided frame scan) are
/// built as two modes of this one screen, per the design README's own
/// recommendation for the safest reading of an undecided brief.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({
    super.key,
    this.boundReleaseId,
    this.boundSetSlotNumber,
    this.startAtUnsortedTray = false,
  });

  final String? boundReleaseId;
  final String? boundSetSlotNumber;
  final bool startAtUnsortedTray;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with CameraControllerMixin {
  late CaptureMode _mode = widget.boundSetSlotNumber != null
      ? CaptureMode.guided
      : CaptureMode.burst;
  bool _burstContinuous = true;
  bool _autoShutter = true;
  FlashMode _flash = FlashMode.off;
  final List<String> _shotPaths = [];
  final String _side = 'Front';
  bool _gridOverlay = false;

  @override
  void initState() {
    super.initState();
    initCamera();
  }

  @override
  void dispose() {
    disposeCamera();
    super.dispose();
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

  Future<void> _onBurstShutter() async {
    final file = await _takeShot();
    if (file == null) return;
    setState(() => _shotPaths.add(file.path));
  }

  void _reviewBurst() {
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: captureRouteName),
        builder: (_) => BatchTriageScreen(
          shotPaths: List.of(_shotPaths),
          boundReleaseId: widget.boundReleaseId,
        ),
      ),
    ).then((_) => setState(() => _shotPaths.clear()));
  }

  Future<void> _onGuidedShutter() async {
    final file = await _takeShot();
    if (file == null) return;
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: captureRouteName),
        builder: (_) => CropRetakeScreen(
          photoPath: file.path,
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
        shotPaths: const [],
        boundReleaseId: widget.boundReleaseId,
        useUnsortedTray: true,
      );
    }

    return Scaffold(
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
                    onPressed: () => Navigator.pop(context),
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
                    onSelectionChanged: (s) => setState(() => _mode = s.first),
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
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CameraPreview(cameraController!),
                            if (_gridOverlay) const _GridOverlay(),
                            _mode == CaptureMode.burst
                                ? _CardGuide(hint: 'Keep shooting')
                                : _GuidedGuide(auto: _autoShutter),
                          ],
                        ),
                      ),
                    ),
            ),
            if (_mode == CaptureMode.burst)
              _BurstControls(
                continuous: _burstContinuous,
                onModeChanged: (v) => setState(() => _burstContinuous = v),
                shotCount: _shotPaths.length,
                onShutter: _onBurstShutter,
                onReview: _shotPaths.isEmpty ? null : _reviewBurst,
                recentPaths: _shotPaths.reversed.take(6).toList(),
                onPathEdited: (oldPath, newPath) => setState(() {
                  final i = _shotPaths.indexOf(oldPath);
                  if (i != -1) _shotPaths[i] = newPath;
                }),
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

class _CardGuide extends StatelessWidget {
  const _CardGuide({required this.hint});

  final String hint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AspectRatio(
            aspectRatio: 5 / 7,
            child: FractionallySizedBox(
              widthFactor: 0.7,
              child: CustomPaint(painter: _CornerBracketsPainter()),
            ),
          ),
          const SizedBox(height: 12),
          Text(hint, style: const TextStyle(color: Colors.white70)),
        ],
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
  const _GuidedGuide({required this.auto});

  final bool auto;

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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AspectRatio(
            aspectRatio: 5 / 7,
            child: FractionallySizedBox(
              widthFactor: 0.72,
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
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(_status, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
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
    required this.onShutter,
    required this.onReview,
    required this.recentPaths,
    required this.onPathEdited,
  });

  final bool continuous;
  final ValueChanged<bool> onModeChanged;
  final int shotCount;
  final VoidCallback onShutter;
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
                          Text(
                            '$shotCount shot',
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
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
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
                    child: Text('Done · review $shotCount'),
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
