import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../data/photo_store.dart';

/// Reusable post-capture photo editor: pinch-zoom + pan the photo under a
/// fixed, centered crop frame (the frame IS the InteractiveViewer's
/// viewport — whatever's visible inside it is what gets cropped), plus
/// quarter-turn rotate and a recenter action. Used for card photos and
/// release cover photos alike; the capture flow's own draggable-corner
/// cropper (`CropRetakeScreen`) is left untouched.
///
/// Rotation is applied immediately to the in-memory decoded image (rather
/// than deferred to save time) so the crop math only ever has to reason
/// about one, always-current, always-consistent set of pixel dimensions.
class PhotoEditorScreen extends StatefulWidget {
  const PhotoEditorScreen({
    super.key,
    required this.sourcePath,
    required this.aspectRatio,
    this.title = 'Edit photo',
  });

  final String sourcePath;
  final double aspectRatio;
  final String title;

  @override
  State<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

class _PhotoEditorScreenState extends State<PhotoEditorScreen> {
  img.Image? _image;
  Uint8List? _displayBytes; // encoded bytes for the current _image
  final _transformController = TransformationController();
  Size? _viewportSize;
  bool _saving = false;
  bool _loadError = false;
  bool _centered = false; // hides the viewer until the initial fit is set

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bytes = await File(widget.sourcePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (!mounted) return;
    if (decoded == null) {
      setState(() => _loadError = true);
      return;
    }
    setState(() {
      _image = decoded;
      _displayBytes = img.encodeJpg(decoded, quality: 92);
    });
  }

  void _centerAndFit() {
    final image = _image;
    final viewport = _viewportSize;
    if (image == null || viewport == null) return;
    final coverScale = math.max(
      viewport.width / image.width,
      viewport.height / image.height,
    );
    final dx = (viewport.width - image.width * coverScale) / 2;
    final dy = (viewport.height - image.height * coverScale) / 2;
    _transformController.value = Matrix4.identity()
      ..translate(dx, dy)
      ..scale(coverScale);
    if (!_centered) setState(() => _centered = true);
  }

  Future<void> _rotate() async {
    final image = _image;
    if (image == null) return;
    final rotated = img.copyRotate(image, angle: 90);
    setState(() {
      _image = rotated;
      _displayBytes = img.encodeJpg(rotated, quality: 92);
      _centered = false;
    });
    // Wait a frame so the new AspectRatio/viewport (unchanged, but the
    // image's own w/h swapped) is laid out before re-centering against it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerAndFit());
  }

  double _coverScale() {
    final image = _image!;
    final viewport = _viewportSize!;
    return math.max(viewport.width / image.width, viewport.height / image.height);
  }

  Future<void> _save() async {
    final image = _image;
    final viewport = _viewportSize;
    if (image == null || viewport == null || _saving) return;
    setState(() => _saving = true);

    final inverse = Matrix4.inverted(_transformController.value);
    final topLeft = MatrixUtils.transformPoint(inverse, Offset.zero);
    final bottomRight = MatrixUtils.transformPoint(
      inverse,
      Offset(viewport.width, viewport.height),
    );
    final x = topLeft.dx.clamp(0, image.width.toDouble()).round();
    final y = topLeft.dy.clamp(0, image.height.toDouble()).round();
    final w = (bottomRight.dx - topLeft.dx)
        .clamp(1, image.width - x)
        .round();
    final h = (bottomRight.dy - topLeft.dy)
        .clamp(1, image.height - y)
        .round();

    final cropped = img.copyCrop(
      image,
      x: x,
      y: y,
      width: math.max(1, w),
      height: math.max(1, h),
    );

    final dir = await getTemporaryDirectory();
    final outFile = File(p.join(dir.path, '${const Uuid().v4()}.jpg'));
    await outFile.writeAsBytes(img.encodeJpg(cropped, quality: 90));
    final savedPath = await PhotoStore.instance.save(outFile);

    if (!mounted) return;
    Navigator.pop(context, savedPath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: _image == null || _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _loadError
                  ? const Text(
                      "Couldn't read that photo",
                      style: TextStyle(color: Colors.white70),
                    )
                  : _image == null
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Padding(
                      padding: const EdgeInsets.all(16),
                      child: AspectRatio(
                        aspectRatio: widget.aspectRatio,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final size = Size(
                              constraints.maxWidth,
                              constraints.maxHeight,
                            );
                            if (_viewportSize != size) {
                              _viewportSize = size;
                              WidgetsBinding.instance.addPostFrameCallback(
                                (_) => _centerAndFit(),
                              );
                            }
                            return Opacity(
                              opacity: _centered ? 1 : 0,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: ClipRect(
                                  child: InteractiveViewer(
                                    transformationController:
                                        _transformController,
                                    constrained: false,
                                    boundaryMargin: EdgeInsets.zero,
                                    minScale: _viewportSize == null
                                        ? 0.1
                                        : _coverScale(),
                                    maxScale: _viewportSize == null
                                        ? 10
                                        : _coverScale() * 4,
                                    child: SizedBox(
                                      width: _image!.width.toDouble(),
                                      height: _image!.height.toDouble(),
                                      child: Image.memory(
                                        _displayBytes!,
                                        fit: BoxFit.fill,
                                        gaplessPlayback: true,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  onPressed: _image == null ? null : _rotate,
                  icon: const Icon(Icons.rotate_90_degrees_ccw, color: Colors.white),
                  label: const Text('Rotate', style: TextStyle(color: Colors.white)),
                ),
                TextButton.icon(
                  onPressed: _image == null ? null : _centerAndFit,
                  icon: const Icon(Icons.filter_center_focus, color: Colors.white),
                  label: const Text('Recenter', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
