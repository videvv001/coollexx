import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pokedex_tcg/data/binder_page_detector.dart';

/// A synthetic binder page: [cols]x[rows] cards in dark pockets.
///
/// Built to match what a real photographed page actually looks like to the
/// detector, because an earlier, friendlier fake (thick gaps, uniformly
/// textured cards) passed while every real photo detected nothing:
///
///  * pockets are **dark** and the gaps between them are **thin** — a few
///    percent of a card's width, not a tenth of it;
///  * a card is a **light printed border** around artwork that is partly
///    dark, including one dark block running out to the card's own edge, so
///    each card reaches the detector as a ragged ring rather than a solid
///    rectangle.
Uint8List syntheticPage({
  int cols = 3,
  int rows = 3,
  int cardW = 240,
  int cardH = 336,
  int gap = 10,
  Set<int> emptySlots = const {},
  double tiltDegrees = 0,
  double lightingFalloff = 0,
}) {
  final w = cols * cardW + (cols + 1) * gap;
  final h = rows * cardH + (rows + 1) * gap;
  final page = img.Image(width: w, height: h);
  img.fill(page, color: img.ColorRgb8(24, 24, 28)); // dark pocket plastic

  final rng = Random(7);
  final border = (cardW * 0.06).round();
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      if (emptySlots.contains(r * cols + c)) continue;
      final x0 = gap + c * (cardW + gap);
      final y0 = gap + r * (cardH + gap);

      // The light printed frame, and mid-bright artwork inside it.
      img.fillRect(
        page,
        x1: x0,
        y1: y0,
        x2: x0 + cardW - 1,
        y2: y0 + cardH - 1,
        color: img.ColorRgb8(236, 236, 232),
      );
      for (var y = y0 + border; y < y0 + cardH - border; y++) {
        for (var x = x0 + border; x < x0 + cardW - border; x++) {
          final v = 150 + rng.nextInt(80);
          page.setPixelRgb(x, y, v, v - rng.nextInt(40), v - rng.nextInt(60));
        }
      }
      // Dark artwork, one block of it bleeding out through the frame — the
      // thing that makes a card a ring instead of a filled shape.
      img.fillRect(
        page,
        x1: x0 + (cardW * 0.15).round(),
        y1: y0 + (cardH * 0.2).round(),
        x2: x0 + (cardW * 0.6).round(),
        y2: y0 + (cardH * 0.55).round(),
        color: img.ColorRgb8(18, 20, 30),
      );
      img.fillRect(
        page,
        x1: x0,
        y1: y0 + (cardH * 0.7).round(),
        x2: x0 + (cardW * 0.35).round(),
        y2: y0 + (cardH * 0.8).round(),
        color: img.ColorRgb8(15, 15, 22),
      );
    }
  }
  if (lightingFalloff > 0) {
    // Bright at the top, falling away toward the bottom — a page lit from
    // one side, or held under a single lamp.
    for (var y = 0; y < h; y++) {
      final k = 1 - lightingFalloff * (y / h);
      for (var x = 0; x < w; x++) {
        final p = page.getPixel(x, y);
        page.setPixelRgb(x, y, p.r * k, p.g * k, p.b * k);
      }
    }
  }
  return img.encodeJpg(
    tiltDegrees == 0 ? page : img.copyRotate(page, angle: tiltDegrees),
    quality: 92,
  );
}

void main() {
  test('finds every card on a 3x3 page, in reading order', () {
    final scan = detectCardsOnPage(syntheticPage());

    expect(scan.cardCount, 9);
    expect(scan.cardJpgs.length, 9);

    for (var row = 0; row < 3; row++) {
      final inRow = scan.quads.sublist(row * 3, row * 3 + 3);
      final xs = inRow.map((q) => q.center.dx).toList();
      expect(xs, orderedEquals(List.of(xs)..sort()), reason: 'row $row');
      for (final q in inRow) {
        expect(
          (q.center.dy - inRow.first.center.dy).abs(),
          lessThan(40),
          reason: 'row $row sits at one height',
        );
      }
    }
    expect(scan.quads[0].center.dy, lessThan(scan.quads[3].center.dy));
    expect(scan.quads[3].center.dy, lessThan(scan.quads[6].center.dy));
  });

  test('cards are not merged across the thin gap between pockets', () {
    // The failure the first pass shipped with: every card fused into one
    // blob, which then failed the size filter and yielded nothing at all.
    final scan = detectCardsOnPage(syntheticPage(gap: 6));

    expect(scan.cardCount, 9);
  });

  test('crops come out upright at card aspect', () {
    final scan = detectCardsOnPage(syntheticPage());

    for (final jpg in scan.cardJpgs) {
      final crop = img.decodeJpg(jpg)!;
      expect(crop.width, lessThan(crop.height), reason: 'portrait');
      expect(crop.width / crop.height, closeTo(5 / 7, 0.02));
    }
  });

  test('a landscape card is rotated upright, not squashed', () {
    final scan = detectCardsOnPage(
      syntheticPage(cols: 3, rows: 1, cardW: 336, cardH: 240),
    );

    expect(scan.cardCount, 3);
    for (final jpg in scan.cardJpgs) {
      final crop = img.decodeJpg(jpg)!;
      expect(crop.width, lessThan(crop.height));
    }
  });

  test('a tilted page still yields every card in reading order', () {
    // Nobody photographs a binder square-on. 6 degrees staircases every
    // row's centres, which the row grouping and the per-side quad fit both
    // have to survive.
    final scan = detectCardsOnPage(syntheticPage(tiltDegrees: 6));

    expect(scan.cardCount, 9);
    for (var row = 0; row < 3; row++) {
      final xs = scan.quads
          .sublist(row * 3, row * 3 + 3)
          .map((q) => q.center.dx)
          .toList();
      expect(xs, orderedEquals(List.of(xs)..sort()), reason: 'row $row');
    }
  });

  test('an unevenly lit page still yields every card', () {
    // The second bug this shipped with: one threshold for the whole page
    // means cards in its dim half fall under it, come out as broken rings
    // and get under-covered by their own hull. Measured on a real
    // hand-held photo before it was fixed — a gold-framed card in the dark
    // corner was the one card of twenty-four that went missing.
    final scan = detectCardsOnPage(syntheticPage(lightingFalloff: 0.55));

    expect(scan.cardCount, 9);
  });

  test('empty binder slots are simply not detected', () {
    final scan = detectCardsOnPage(syntheticPage(emptySlots: {0, 4, 8}));

    expect(scan.cardCount, 6);
  });

  test('an undecodable page throws rather than returning junk', () {
    // decodeImage doesn't only return null on bad input — sniffing a
    // truncated file reads past the end of the buffer and throws.
    expect(
      () => detectCardsOnPage(Uint8List.fromList([1, 2, 3, 4])),
      throwsA(isA<BinderPageDecodeException>()),
    );
  });
}
