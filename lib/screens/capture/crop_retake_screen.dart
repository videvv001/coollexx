import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../data/photo_store.dart';
import 'camera_controller_mixin.dart';
import 'name_tag_file_screen.dart';

/// 1c step 2 — Crop & retake. A detected photo with four draggable corner
/// handles (implemented as an axis-aligned crop rect — the wireframe's
/// corner handles without the added complexity of true perspective
/// correction), Rotate / Straighten / Fill frame, and an optional second
/// shot for the back of the card.
class CropRetakeScreen extends StatefulWidget {
  const CropRetakeScreen({
    super.key,
    required this.photoPath,
    required this.side,
    this.boundReleaseId,
    this.boundSetSlotNumber,
  });

  final String photoPath;
  final String side;
  final String? boundReleaseId;
  final String? boundSetSlotNumber;

  @override
  State<CropRetakeScreen> createState() => _CropRetakeScreenState();
}

class _CropRetakeScreenState extends State<CropRetakeScreen> {
  Rect _cropRect = const Rect.fromLTWH(0.05, 0.05, 0.9, 0.9);
  int _quarterTurns = 0;
  double _straighten = 0;
  String? _backPath;
  bool _processing = false;

  void _dragCorner(String corner, Offset delta, Size boxSize) {
    setState(() {
      double left = _cropRect.left,
          top = _cropRect.top,
          right = _cropRect.right,
          bottom = _cropRect.bottom;
      final dx = delta.dx / boxSize.width;
      final dy = delta.dy / boxSize.height;
      switch (corner) {
        case 'tl':
          left += dx;
          top += dy;
          break;
        case 'tr':
          right += dx;
          top += dy;
          break;
        case 'bl':
          left += dx;
          bottom += dy;
          break;
        case 'br':
          right += dx;
          bottom += dy;
          break;
      }
      const minSize = 0.15;
      left = left.clamp(0.0, right - minSize);
      top = top.clamp(0.0, bottom - minSize);
      right = right.clamp(left + minSize, 1.0);
      bottom = bottom.clamp(top + minSize, 1.0);
      _cropRect = Rect.fromLTRB(left, top, right, bottom);
    });
  }

  Future<String> _process(String sourcePath) async {
    final bytes = await File(sourcePath).readAsBytes();
    var decoded = img.decodeImage(bytes);
    if (decoded == null) return sourcePath;
    if (_quarterTurns != 0) {
      decoded = img.copyRotate(decoded, angle: 90.0 * _quarterTurns);
    }
    if (_straighten != 0) {
      decoded = img.copyRotate(decoded, angle: _straighten);
    }
    final x = (_cropRect.left * decoded.width).round();
    final y = (_cropRect.top * decoded.height).round();
    final w = (_cropRect.width * decoded.width).round();
    final h = (_cropRect.height * decoded.height).round();
    final cropped = img.copyCrop(
      decoded,
      x: x,
      y: y,
      width: math.max(1, w),
      height: math.max(1, h),
    );

    final dir = await getTemporaryDirectory();
    final outFile = File(p.join(dir.path, '${const Uuid().v4()}.jpg'));
    await outFile.writeAsBytes(img.encodeJpg(cropped, quality: 90));
    return PhotoStore.instance.save(outFile);
  }

  Future<void> _captureBack() async {
    final path = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _QuickShotScreen()),
    );
    if (path != null) setState(() => _backPath = path);
  }

  Future<void> _next() async {
    setState(() => _processing = true);
    final frontPath = await _process(widget.photoPath);
    String? backPath;
    if (_backPath != null) {
      backPath = await PhotoStore.instance.save(File(_backPath!));
    }
    if (!mounted) return;
    setState(() => _processing = false);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NameTagFileScreen(
          photoPaths: [frontPath, if (backPath != null) backPath],
          boundReleaseId: widget.boundReleaseId,
          boundSetSlotNumber: widget.boundSetSlotNumber,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Crop · ${widget.side}'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 5 / 7,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final boxSize = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(File(widget.photoPath), fit: BoxFit.cover),
                        Positioned(
                          left: _cropRect.left * boxSize.width,
                          top: _cropRect.top * boxSize.height,
                          width: _cropRect.width * boxSize.width,
                          height: _cropRect.height * boxSize.height,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                        for (final corner in ['tl', 'tr', 'bl', 'br'])
                          _handle(corner, boxSize),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _quarterTurns = (_quarterTurns + 1) % 4),
                  icon: const Icon(
                    Icons.rotate_90_degrees_ccw,
                    color: Colors.white,
                  ),
                  label: const Text(
                    'Rotate',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _showStraighten(context),
                  icon: const Icon(Icons.straighten, color: Colors.white),
                  label: const Text(
                    'Straighten',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => setState(
                    () => _cropRect = const Rect.fromLTWH(0, 0, 1, 1),
                  ),
                  icon: const Icon(Icons.crop_free, color: Colors.white),
                  label: const Text(
                    'Fill frame',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(
                    File(widget.photoPath),
                    width: 48,
                    height: 64,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _captureBack,
                  child: DottedBox(
                    child: _backPath != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.file(
                              File(_backPath!),
                              width: 48,
                              height: 64,
                              fit: BoxFit.cover,
                            ),
                          )
                        : const SizedBox(
                            width: 48,
                            height: 64,
                            child: Icon(Icons.add, color: Colors.white54),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '+ back (optional)',
                  style: TextStyle(color: Colors.white54),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _processing ? null : _next,
                  child: _processing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Next — name & file'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showStraighten(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Straighten',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Slider(
                value: _straighten,
                min: -15,
                max: 15,
                onChanged: (v) {
                  setSheetState(() => _straighten = v);
                  setState(() {});
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _handle(String corner, Size boxSize) {
    final dx = corner.contains('l') ? _cropRect.left : _cropRect.right;
    final dy = corner.contains('t') ? _cropRect.top : _cropRect.bottom;
    return Positioned(
      left: dx * boxSize.width - 12,
      top: dy * boxSize.height - 12,
      child: GestureDetector(
        onPanUpdate: (details) => _dragCorner(corner, details.delta, boxSize),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black26),
          ),
        ),
      ),
    );
  }
}

class DottedBox extends StatelessWidget {
  const DottedBox({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white38),
        borderRadius: BorderRadius.circular(6),
      ),
      child: child,
    );
  }
}

class _QuickShotScreen extends StatefulWidget {
  const _QuickShotScreen();

  @override
  State<_QuickShotScreen> createState() => _QuickShotScreenState();
}

class _QuickShotScreenState extends State<_QuickShotScreen>
    with CameraControllerMixin {
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

  Future<void> _shoot() async {
    final controller = cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    final file = await controller.takePicture();
    if (mounted) Navigator.pop(context, file.path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Back of card'),
      ),
      body: Column(
        children: [
          Expanded(
            child: cameraError != null
                ? Center(
                    child: Text(
                      cameraError!,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  )
                : cameraReady
                ? CameraPreview(cameraController!)
                : const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: GestureDetector(
              onTap: _shoot,
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
        ],
      ),
    );
  }
}
