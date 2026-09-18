import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Shared camera lifecycle for the capture screens. Handles the case where
/// no camera is available (permission denied, no hardware, or — as in this
/// build environment — no device at all) with a plain error state instead
/// of crashing.
mixin CameraControllerMixin<T extends StatefulWidget> on State<T> {
  CameraController? cameraController;
  String? cameraError;
  bool cameraReady = false;

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
      if (!mounted) return;
      setState(() => cameraReady = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => cameraError = 'Camera unavailable: $e');
    }
  }

  void disposeCamera() {
    cameraController?.dispose();
  }
}
