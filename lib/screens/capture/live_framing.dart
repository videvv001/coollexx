import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../data/photo_store.dart';

/// The card aspect ratio (width / height) used throughout capture — same
/// value `PhotoEditorScreen` and the folder grid already crop/display to.
const double kCardAspect = 5 / 7;

/// The largest centered [targetAspect] (width/height) rectangle that fits
/// inside a [previewAspect] (width/height) box, expressed as width/height
/// factors of that box (0–1). Used both to size the live on-screen capture
/// frame and, applied to the captured photo's own width/height, to crop it
/// to the same region — so what the frame shows is exactly what gets kept.
({double width, double height}) captureFrameFraction({
  required double previewAspect,
  required double targetAspect,
}) {
  if (previewAspect >= targetAspect) {
    return (width: targetAspect / previewAspect, height: 1.0);
  }
  return (width: 1.0, height: previewAspect / targetAspect);
}

/// Crops a just-captured photo down to the same centered [targetAspect]
/// region the live capture frame showed, then saves it via [PhotoStore].
/// The decode/crop/encode runs in a background isolate (`compute`) so burst
/// shooting never blocks the UI thread on it.
Future<String> cropToFraming(String sourcePath, double targetAspect) async {
  final bytes = await File(sourcePath).readAsBytes();
  final jpegBytes = await compute(
    _cropJpegBytes,
    _CropJob(bytes, targetAspect),
  );
  final dir = await getTemporaryDirectory();
  final outFile = File(p.join(dir.path, '${const Uuid().v4()}.jpg'));
  await outFile.writeAsBytes(jpegBytes);
  return PhotoStore.instance.save(outFile);
}

class _CropJob {
  const _CropJob(this.bytes, this.targetAspect);
  final Uint8List bytes;
  final double targetAspect;
}

// Top-level so `compute` can send it to a background isolate.
Uint8List _cropJpegBytes(_CropJob job) {
  final decoded = img.decodeImage(job.bytes);
  if (decoded == null) return job.bytes;
  final frame = captureFrameFraction(
    previewAspect: decoded.width / decoded.height,
    targetAspect: job.targetAspect,
  );
  final cropW = (decoded.width * frame.width).round().clamp(1, decoded.width);
  final cropH = (decoded.height * frame.height).round().clamp(
    1,
    decoded.height,
  );
  final x = ((decoded.width - cropW) / 2).round();
  final y = ((decoded.height - cropH) / 2).round();
  final cropped = img.copyCrop(
    decoded,
    x: x,
    y: y,
    width: cropW,
    height: cropH,
  );
  return img.encodeJpg(cropped, quality: 90);
}
