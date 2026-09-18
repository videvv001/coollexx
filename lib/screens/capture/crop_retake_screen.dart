import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../data/photo_store.dart';
import '../shared/photo_editor_screen.dart';
import 'camera_controller_mixin.dart';
import 'name_tag_file_screen.dart';

/// 1c step 2 — Crop & retake. Delegates the actual crop/zoom/rotate to the
/// shared `PhotoEditorScreen` (pushed as soon as this screen appears), then
/// shows the existing "optional back-of-card shot + Next" step once the
/// front photo comes back edited and saved.
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
  String? _frontPath;
  String? _backPath;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _editFront());
  }

  Future<void> _editFront() async {
    final saved = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoEditorScreen(
          sourcePath: widget.photoPath,
          aspectRatio: 5 / 7,
          title: 'Crop · ${widget.side}',
        ),
      ),
    );
    if (!mounted) return;
    if (saved == null) {
      Navigator.pop(context);
      return;
    }
    setState(() => _frontPath = saved);
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
          photoPaths: [_frontPath!, if (backPath != null) backPath],
          boundReleaseId: widget.boundReleaseId,
          boundSetSlotNumber: widget.boundSetSlotNumber,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_frontPath == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
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
                child: Image.file(File(_frontPath!), fit: BoxFit.cover),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _editFront,
                  icon: const Icon(Icons.crop, color: Colors.white),
                  label: const Text(
                    'Re-edit',
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
                    File(_frontPath!),
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
                ? Center(
                    child: AspectRatio(
                      aspectRatio: 1 / cameraController!.value.aspectRatio,
                      child: CameraPreview(cameraController!),
                    ),
                  )
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
