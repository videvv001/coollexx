import 'dart:io';
import 'dart:ui' show Rect;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

import '../models/release_category.dart';
import 'card_text_layout.dart';

export 'card_text_layout.dart' show CardTextGuess, OcrBlock, classifyCardText;

// Many cards are Japanese prints, so Latin-only OCR either misses the
// (kana/kanji) name entirely or, worse, latches onto the one Latin-script
// label it *can* read nearby — e.g. the "CHARACTER" kind banner printed
// just above a One Piece card's name — and reports that as the name.
// Running the Japanese script model too lets it actually read the name
// text; see the Android/iOS setup this needs in the project's build files
// (google_mlkit_text_recognition only bundles Latin by default).
const _scripts = [TextRecognitionScript.latin, TextRecognitionScript.japanese];

/// Scans [imagePath] with on-device text recognition (no network call, no
/// server) and classifies what it finds into card fields — see
/// `classifyCardText`, which holds all the layout logic and is where to
/// look (and where the tests point) when a field comes back wrong.
///
/// Never throws; a field is null when the read was ambiguous.
Future<CardTextGuess> scanCardText(
  String imagePath,
  ReleaseCategory category,
) async {
  final decoded = img.decodeImage(await File(imagePath).readAsBytes());
  if (decoded == null) return const CardTextGuess();

  final blocks = <OcrBlock>[];
  for (final script in _scripts) {
    final recognizer = TextRecognizer(script: script);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(imagePath),
      );
      blocks.addAll(
        result.blocks.map((b) => _toOcrBlock(b, decoded.width, decoded.height)),
      );
    } catch (_) {
      // That script's model may be unavailable (e.g. still downloading on
      // first use) — the other script(s)/fields can still succeed.
    } finally {
      await recognizer.close();
    }
  }
  return classifyCardText(blocks, category);
}

/// Normalizes a block to 0..1 of the card image. The capture and upload
/// flows both crop to the card's aspect before this runs, so the image is
/// the card — there's no separate perspective-correction step to key off.
OcrBlock _toOcrBlock(TextBlock block, int imageWidth, int imageHeight) {
  final box = block.boundingBox;
  return OcrBlock(
    text: block.text,
    box: Rect.fromLTRB(
      box.left / imageWidth,
      box.top / imageHeight,
      box.right / imageWidth,
      box.bottom / imageHeight,
    ),
    lineCount: block.lines.length,
    confidence: _meanConfidence(block),
  );
}

/// Mean of the per-line confidences ML Kit reports. Android-only — every
/// line comes back null on iOS, which yields null here rather than a
/// misleading zero.
double? _meanConfidence(TextBlock block) {
  final scores = block.lines
      .map((l) => l.confidence)
      .whereType<double>()
      .toList();
  if (scores.isEmpty) return null;
  return scores.reduce((a, b) => a + b) / scores.length;
}
