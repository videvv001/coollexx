import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Shared camera lifecycle for the capture screens. Handles the case where
/// no camera is available (permission denied, no hardware, or — as in this
/// build environment — no device at all) with a plain error state instead
/// of crashing.
///
/// Also owns native camera zoom (`setZoomLevel`) — real optical/logical
/// zoom from the platform camera, not a scaled-up preview — so pinch
/// gestures in the capture screen affect the actual sensor framing and
/// carry through to `takePicture()` consistently.
mixin CameraControllerMixin<T extends StatefulWidget> on State<T> {
  CameraController? cameraController;
  String? cameraError;
  bool cameraReady = false;

  double minZoomLevel = 1.0;
  double maxZoomLevel = 1.0;
  double currentZoom = 1.0;
  bool _zoomBusy = false;

  Future<void> initCamera({
    ResolutionPreset resolution = ResolutionPreset.high,
  }) async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted) return;
        setState(() => cameraError = 'No camera available on this device.');
        return;
      }
      final controller = CameraController(
        cameras.first,
        resolution,
        enableAudio: false,
      );
      cameraController = controller;
      await controller.initialize();
      try {
        minZoomLevel = await controller.getMinZoomLevel();
        maxZoomLevel = await controller.getMaxZoomLevel();
        currentZoom = minZoomLevel;
      } catch (_) {
        // Zoom not supported on this device/platform — stay at 1.0/1.0.
      }
      if (!mounted) return;
      setState(() => cameraReady = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => cameraError = 'Camera unavailable: $e');
    }
  }

  /// Sets native camera zoom, clamped to the device's supported range.
  /// Drops overlapping calls (e.g. from a fast pinch drag) rather than
  /// queuing them, so the platform channel never backs up — the next
  /// gesture update picks up the latest target anyway.
  Future<void> setZoom(double zoom) async {
    final controller = cameraController;
    if (controller == null || _zoomBusy) return;
    final clamped = zoom.clamp(minZoomLevel, maxZoomLevel);
    if ((clamped - currentZoom).abs() < 0.01) return;
    _zoomBusy = true;
    currentZoom = clamped;
    if (mounted) setState(() {});
    try {
      await controller.setZoomLevel(clamped);
    } catch (_) {
      // Ignore — e.g. camera mid-teardown.
    }
    _zoomBusy = false;
  }

  Future<void> resetZoom() => setZoom(minZoomLevel);

  /// Releases the camera hardware. Resets `cameraController`/`cameraReady`
  /// (not just fire-and-forget disposal) so callers can tell there's no
  /// live camera right now — important for screens that pause the camera
  /// on app backgrounding and reacquire it on resume rather than only ever
  /// disposing once when the whole screen is torn down.
  void disposeCamera() {
    cameraController?.dispose();
    cameraController = null;
    cameraReady = false;
  }
}
