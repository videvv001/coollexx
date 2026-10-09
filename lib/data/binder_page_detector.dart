import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'photo_store.dart';

/// One detected card on a binder page. [corners] are its four corners in
/// the coordinate space of the page image they were found in (see
/// `BinderPageScan.pageWidth`/`pageHeight`), ordered top-left, top-right,
/// bottom-right, bottom-left *of the card itself* — so a card sitting
/// sideways in its pocket has its own top edge first, not the image's.
class CardQuad {
  const CardQuad(this.corners);

  final List<Offset> corners;

  Offset get center =>
      corners.reduce((a, b) => a + b) / corners.length.toDouble();

  /// Axis-aligned bounds, for cheap row grouping and overlay layout.
  ({double left, double top, double right, double bottom}) get bounds => (
    left: corners.map((c) => c.dx).reduce(math.min),
    top: corners.map((c) => c.dy).reduce(math.min),
    right: corners.map((c) => c.dx).reduce(math.max),
    bottom: corners.map((c) => c.dy).reduce(math.max),
  );
}

/// The result of processing one binder-page image: a display-sized copy of
/// the page, the card quads found on it, and one normalized JPEG per quad.
///
/// The page copy is returned rather than the original bytes so the caller
/// never has to decode the full-resolution source again — that decode lives
/// and dies inside the isolate this runs on, which is what keeps a 20-page
/// upload from holding twenty full-size bitmaps at once.
class BinderPageScan {
  const BinderPageScan({
    required this.pageJpg,
    required this.pageWidth,
    required this.pageHeight,
    required this.quads,
    required this.cardJpgs,
  });

  final Uint8List pageJpg;
  final int pageWidth;
  final int pageHeight;
  final List<CardQuad> quads;

  /// One JPEG per entry in [quads], same order.
  final List<Uint8List> cardJpgs;

  int get cardCount => quads.length;
}

/// Thrown when a page image can't be decoded at all. A page that fails this
/// way is reported and skipped — never allowed to take its session's other
/// pages down with it.
class BinderPageDecodeException implements Exception {
  const BinderPageDecodeException();
  @override
  String toString() => "Couldn't read that image";
}

// ---------------------------------------------------------------------------
// Tuning. Every threshold is a fraction of the image, never a pixel count,
// so the same numbers hold for a 2MP upload and a 48MP camera shot.
// ---------------------------------------------------------------------------

/// Longest side of the image detection actually runs on. Contour work is
/// O(pixels) in pure Dart, and a card border is still several pixels wide
/// at this size; the quads found here are scaled back up and the crops are
/// taken from the full-resolution original.
const _detectionMaxSide = 900;

/// A card's own aspect (width / height) — the same 5/7 the capture frame,
/// photo editor and folder grid use (`kCardAspect` in `live_framing.dart`).
/// Crops are normalized to it so `classifyCardText`'s positional bands land
/// where they do for a single-card photo.
const _cardAspect = 5 / 7;

/// Cap on a crop's height: bounds both memory and OCR cost for a page of
/// nine. Small print still resolves at this height.
const _cardMaxHeight = 1100;

/// All measured against the card's *hull*, not its lit pixels — see
/// [_findQuads] for why a card arrives as a ring rather than a filled shape.
/// The observed spread over real 3x3 photos is 5-10% area, 0.63-0.90 aspect
/// and 0.82-0.99 fill, so these sit just outside that.
const _minAreaFraction = 0.015; // a card on a dense 4x5 page, shot loosely
const _maxAreaFraction = 0.35; // bigger than this is the page, not a card
const _minHullFill = 0.80; // hull area / its min-area rect's area
const _minAspect = 0.55; // short/long side; a card is 0.71, and neither
const _maxAspect = 0.95; // glare nor a sleeve moves it far off that

/// Radius of the neighbourhood each pixel's threshold is measured against,
/// as a fraction of the image's long side. Deliberately large — a third of
/// the page, several cards across — so it tracks how the light fell without
/// ever adapting to a single card's own artwork or the pocket's mesh
/// texture, which a small window would latch onto and shred the mask.
const _localWindowFraction = 0.33;

/// A speck too small to be worth hulling, as a fraction of the image.
const _minBlobFraction = 0.0008;

/// How far a candidate's area may sit from the median candidate's before
/// it's treated as something that merely looks card-shaped. Cards on one
/// page are all the same size, which is the cheapest signal there is for
/// throwing out a stray reflection or a slice of binder ring.
const _minSizeOfMedian = 0.55;
const _maxSizeOfMedian = 1.8;

/// Below this many candidates there's no reliable median to compare to.
const _sizeFilterMinCandidates = 4;

/// Detects and crops every card on one binder-page image.
///
/// Pure and self-contained (no plugins, no file I/O) so it can be handed
/// straight to `compute` — see [scanBinderPage] at the bottom of this file,
/// which is what callers actually use.
///
/// Throws [BinderPageDecodeException] if [bytes] isn't a decodable image.
BinderPageScan detectCardsOnPage(Uint8List bytes) {
  // decodeImage doesn't only return null on bad input — sniffing the format
  // of a truncated or corrupt file reads past the end of the buffer and
  // throws. Both mean the same thing to a caller, so both arrive as one
  // exception it can catch per page.
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    throw const BinderPageDecodeException();
  }
  if (decoded == null) throw const BinderPageDecodeException();
  // Gallery images and other camera apps carry rotation in EXIF rather
  // than in the pixels; without this a portrait page detects as a
  // landscape one and every crop comes out on its side.
  final page = img.bakeOrientation(decoded);

  final scale = _detectionMaxSide / math.max(page.width, page.height);
  final small = scale < 1
      ? img.copyResize(
          page,
          width: (page.width * scale).round(),
          height: (page.height * scale).round(),
        )
      : page;

  final quads = _findQuads(small);
  final up = scale < 1 ? 1 / scale : 1.0;

  final cardJpgs = <Uint8List>[];
  for (final q in quads) {
    cardJpgs.add(
      _rectifyCard(page, CardQuad(q.corners.map((c) => c * up).toList())),
    );
  }

  return BinderPageScan(
    // The overlay is drawn on this copy, and the returned quads are
    // expressed in its coordinate space.
    pageJpg: img.encodeJpg(small, quality: 80),
    pageWidth: small.width,
    pageHeight: small.height,
    quads: quads,
    cardJpgs: cardJpgs,
  );
}

// ---------------------------------------------------------------------------
// Detection
// ---------------------------------------------------------------------------

/// Finds card-shaped blobs, in reading order.
///
/// The signal is brightness: a binder's pockets are separated by dark
/// plastic, and every card in this app's games carries a light printed
/// border, so an Otsu split of the page's own luminance cuts exactly along
/// each card's outer edge. Dark artwork inside a card punches holes in that
/// shape and can even reach the border, so a card arrives here as a ragged
/// *ring*, not a filled rectangle — which is why every test below is run
/// against the blob's convex hull rather than its lit pixels.
///
/// ponytail: a card with a genuinely dark border is the blind spot — it
/// merges into the dark gap and is missed. Pokémon and One Piece cards are
/// light-bordered, so this app doesn't meet that case; a game where it does
/// needs a different mask, and [_brightMask] is the only thing that would
/// have to change.
List<CardQuad> _findQuads(img.Image small) {
  final w = small.width;
  final h = small.height;
  final total = w * h;

  final mask = _brightMask(img.grayscale(small.clone()));
  // Two cards nearly touching would otherwise join through their lit
  // borders into one blob whose hull swallows both. Eroding breaks that
  // bridge; `_grow` puts the shaved pixel back on the final quad.
  _erode(mask, w, h);

  final candidates = <({CardQuad quad, double area})>[];
  for (final blob in _components(mask, w, h)) {
    if (blob.length < total * _minBlobFraction) continue;
    final hull = _convexHull(blob);
    if (hull.length < 4) continue;
    final area = _polygonArea(hull);
    if (area < total * _minAreaFraction || area > total * _maxAreaFraction) {
      continue;
    }
    final rect = _minAreaRect(hull);
    if (rect == null) continue;
    final rectArea = rect.width * rect.height;
    if (rectArea <= 0 || area / rectArea < _minHullFill) continue;
    final aspect =
        math.min(rect.width, rect.height) / math.max(rect.width, rect.height);
    if (aspect < _minAspect || aspect > _maxAspect) continue;

    candidates.add((
      quad: CardQuad(_orderForCard(_grow(_refineToQuad(hull, rect), 2))),
      area: area,
    ));
  }

  return _readingOrder(_keepConsistentlySized(candidates));
}

/// Drops candidates whose area sits far from the median one's. Everything
/// reaching here is already card-shaped; this is what separates nine real
/// cards from the tenth shape that merely looked like one — a glare patch,
/// a slice of the binder's own frame — since real cards on a page are all
/// cut to the same size.
List<CardQuad> _keepConsistentlySized(
  List<({CardQuad quad, double area})> candidates,
) {
  if (candidates.length < _sizeFilterMinCandidates) {
    return [for (final c in candidates) c.quad];
  }
  final areas = candidates.map((c) => c.area).toList()..sort();
  final median = areas[areas.length ~/ 2];
  return [
    for (final c in candidates)
      if (c.area >= median * _minSizeOfMedian &&
          c.area <= median * _maxSizeOfMedian)
        c.quad,
  ];
}

/// Shoelace area of a simple polygon.
double _polygonArea(List<Offset> poly) {
  var sum = 0.0;
  for (var i = 0; i < poly.length; i++) {
    final b = poly[(i + 1) % poly.length];
    sum += poly[i].dx * b.dy - b.dx * poly[i].dy;
  }
  return sum.abs() / 2;
}

/// A 0/1 mask of "brighter than this part of the page ought to be".
///
/// Otsu picks the split between lit cards and dark pockets from the page's
/// own histogram, but as a single number for the whole image, which a page
/// lit unevenly defeats: measured on a hand-held photo lit from the top, a
/// gold-framed card in the dark bottom corner fell under the page-wide
/// threshold and came out as a broken ring the hull then under-covered.
///
/// So Otsu's threshold is kept as a *ratio* to the page's mean brightness —
/// the separation it found, expressed independently of exposure — and that
/// ratio is applied against a local mean instead of a global one. The
/// decision stays Otsu's; it just follows the light across the page. Local
/// means come from an integral image, so the window costs four lookups per
/// pixel no matter how wide it is.
Uint8List _brightMask(img.Image image) {
  final w = image.width;
  final h = image.height;
  final total = w * h;

  final lum = Uint8List(total);
  final hist = List<int>.filled(256, 0);
  var sum = 0.0;
  var i = 0;
  for (final p in image) {
    final v = p.luminance.round().clamp(0, 255);
    lum[i++] = v;
    hist[v]++;
    sum += v;
  }
  final mean = sum / total;
  // A blank page has no two humps to separate, and no cards either.
  if (mean <= 0) return Uint8List(total);
  final ratio = _otsuThreshold(hist, total) / mean;

  // Row-prefix then column-prefix: integral[y][x] is the sum of every pixel
  // above and left of it, so any rectangle's sum is four reads.
  final integral = Int64List((w + 1) * (h + 1));
  for (var y = 0; y < h; y++) {
    var rowSum = 0;
    for (var x = 0; x < w; x++) {
      rowSum += lum[y * w + x];
      integral[(y + 1) * (w + 1) + x + 1] =
          integral[y * (w + 1) + x + 1] + rowSum;
    }
  }

  final radius = (math.max(w, h) * _localWindowFraction).round();
  final mask = Uint8List(total);
  for (var y = 0; y < h; y++) {
    final y0 = math.max(0, y - radius);
    final y1 = math.min(h, y + radius + 1);
    for (var x = 0; x < w; x++) {
      final x0 = math.max(0, x - radius);
      final x1 = math.min(w, x + radius + 1);
      final area = (x1 - x0) * (y1 - y0);
      final windowSum =
          integral[y1 * (w + 1) + x1] -
          integral[y0 * (w + 1) + x1] -
          integral[y1 * (w + 1) + x0] +
          integral[y0 * (w + 1) + x0];
      mask[y * w + x] = lum[y * w + x] > (windowSum / area) * ratio ? 1 : 0;
    }
  }
  return mask;
}

/// The grey level that best splits [hist] into two classes, by Otsu's
/// between-class variance.
int _otsuThreshold(List<int> hist, int total) {
  var sum = 0.0;
  for (var i = 0; i < 256; i++) {
    sum += i * hist[i];
  }
  var sumB = 0.0;
  var countB = 0;
  var best = 0.0;
  var threshold = 128;
  for (var t = 0; t < 256; t++) {
    countB += hist[t];
    if (countB == 0) continue;
    final countF = total - countB;
    if (countF == 0) break;
    sumB += t * hist[t];
    final meanB = sumB / countB;
    final meanF = (sum - sumB) / countF;
    final variance = countB * countF * (meanB - meanF) * (meanB - meanF);
    if (variance > best) {
      best = variance;
      threshold = t;
    }
  }
  return threshold;
}

/// 3x3 erosion, one pass, in place.
void _erode(Uint8List mask, int w, int h) {
  final src = Uint8List.fromList(mask);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (src[i] == 0) continue;
      var keep = true;
      for (var dy = -1; dy <= 1 && keep; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h || src[ny * w + nx] == 0) {
            keep = false;
            break;
          }
        }
      }
      if (!keep) mask[i] = 0;
    }
  }
}

/// 8-connected components of the set pixels, as lists of points. Iterative
/// (an explicit stack, not recursion) — a blob here runs to a hundred
/// thousand pixels and a recursive flood fill would blow the stack.
List<List<Offset>> _components(Uint8List mask, int w, int h) {
  final seen = Uint8List(w * h);
  final out = <List<Offset>>[];
  final stack = <int>[];
  for (var start = 0; start < mask.length; start++) {
    if (mask[start] == 0 || seen[start] == 1) continue;
    final blob = <Offset>[];
    stack.add(start);
    seen[start] = 1;
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      final x = i % w;
      final y = i ~/ w;
      blob.add(Offset(x.toDouble(), y.toDouble()));
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          final ni = ny * w + nx;
          if (mask[ni] == 1 && seen[ni] == 0) {
            seen[ni] = 1;
            stack.add(ni);
          }
        }
      }
    }
    out.add(blob);
  }
  return out;
}

/// Andrew's monotone chain. Collinear points are dropped, so the result is
/// a minimal hull.
List<Offset> _convexHull(List<Offset> points) {
  final pts = List.of(
    points,
  )..sort((a, b) => a.dx == b.dx ? a.dy.compareTo(b.dy) : a.dx.compareTo(b.dx));
  if (pts.length < 3) return pts;

  double cross(Offset o, Offset a, Offset b) =>
      (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);

  final lower = <Offset>[];
  for (final p in pts) {
    while (lower.length >= 2 &&
        cross(lower[lower.length - 2], lower.last, p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }
  final upper = <Offset>[];
  for (final p in pts.reversed) {
    while (upper.length >= 2 &&
        cross(upper[upper.length - 2], upper.last, p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }
  lower.removeLast();
  upper.removeLast();
  return [...lower, ...upper];
}

class _RotatedRect {
  const _RotatedRect({
    required this.corners,
    required this.width,
    required this.height,
    required this.angle,
  });

  final List<Offset> corners;
  final double width;
  final double height;

  /// Radians of the side [width] measures.
  final double angle;
}

/// Smallest-area enclosing rectangle, by rotating calipers: for a convex
/// polygon the minimum rectangle always has a side flush with one of the
/// polygon's own edges, so trying each edge's angle is exhaustive.
_RotatedRect? _minAreaRect(List<Offset> hull) {
  _RotatedRect? best;
  var bestArea = double.infinity;
  for (var i = 0; i < hull.length; i++) {
    final a = hull[i];
    final b = hull[(i + 1) % hull.length];
    final angle = math.atan2(b.dy - a.dy, b.dx - a.dx);
    final cos = math.cos(-angle);
    final sin = math.sin(-angle);
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (final p in hull) {
      final x = p.dx * cos - p.dy * sin;
      final y = p.dx * sin + p.dy * cos;
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
      minY = math.min(minY, y);
      maxY = math.max(maxY, y);
    }
    final area = (maxX - minX) * (maxY - minY);
    if (area >= bestArea) continue;
    bestArea = area;
    Offset back(double x, double y) =>
        Offset(x * cos + y * sin, -x * sin + y * cos);
    best = _RotatedRect(
      corners: [
        back(minX, minY),
        back(maxX, minY),
        back(maxX, maxY),
        back(minX, maxY),
      ],
      width: maxX - minX,
      height: maxY - minY,
      angle: angle,
    );
  }
  return best;
}

/// Turns the bounding rectangle into a true quadrilateral by fitting a line
/// to the hull points along each of its four sides and intersecting
/// adjacent fits. This is the step that actually captures perspective: a
/// card photographed at an angle is a trapezoid, and no rectangle describes
/// one without either clipping a corner off or swallowing a neighbour.
///
/// Falls back to the rectangle's own corners whenever a side has too few
/// points to fit or the result is implausible (near-parallel fits intersect
/// somewhere near infinity), so a bad fit degrades to a slightly loose crop
/// rather than a garbage one.
List<Offset> _refineToQuad(List<Offset> hull, _RotatedRect rect) {
  final cos = math.cos(-rect.angle);
  final sin = math.sin(-rect.angle);
  Offset toLocal(Offset p) =>
      Offset(p.dx * cos - p.dy * sin, p.dx * sin + p.dy * cos);
  Offset toWorld(Offset p) =>
      Offset(p.dx * cos + p.dy * sin, -p.dx * sin + p.dy * cos);

  final local = hull.map(toLocal).toList();
  final minX = local.map((p) => p.dx).reduce(math.min);
  final maxX = local.map((p) => p.dx).reduce(math.max);
  final minY = local.map((p) => p.dy).reduce(math.min);
  final maxY = local.map((p) => p.dy).reduce(math.max);
  final w = maxX - minX, h = maxY - minY;
  if (w <= 0 || h <= 0) return rect.corners;

  // Each hull point votes for the side it sits closest to. Points near a
  // corner abstain, so a card's rounded corners can't drag a side's fit
  // off true.
  final top = <Offset>[], bottom = <Offset>[];
  final left = <Offset>[], right = <Offset>[];
  for (final p in local) {
    final d = [p.dy - minY, maxY - p.dy, p.dx - minX, maxX - p.dx];
    final inSpanX = p.dx > minX + w * 0.1 && p.dx < maxX - w * 0.1;
    final inSpanY = p.dy > minY + h * 0.1 && p.dy < maxY - h * 0.1;
    switch (d.indexOf(d.reduce(math.min))) {
      case 0:
        if (inSpanX) top.add(p);
      case 1:
        if (inSpanX) bottom.add(p);
      case 2:
        if (inSpanY) left.add(p);
      case _:
        if (inSpanY) right.add(p);
    }
  }

  // Each side is fitted in whichever axis it's a function of, so no fit can
  // hit the vertical-line singularity of a single y = mx + c form.
  final topFit = _fitLine(top, horizontal: true);
  final bottomFit = _fitLine(bottom, horizontal: true);
  final leftFit = _fitLine(left, horizontal: false);
  final rightFit = _fitLine(right, horizontal: false);
  if (topFit == null ||
      bottomFit == null ||
      leftFit == null ||
      rightFit == null) {
    return rect.corners;
  }

  // y = hz.m*x + hz.c  crossed with  x = vt.m*y + vt.c
  Offset? cross(({double m, double c}) hz, ({double m, double c}) vt) {
    final denom = 1 - hz.m * vt.m;
    if (denom.abs() < 1e-6) return null;
    final y = (hz.m * vt.c + hz.c) / denom;
    return Offset(vt.m * y + vt.c, y);
  }

  final quad = [
    cross(topFit, leftFit),
    cross(topFit, rightFit),
    cross(bottomFit, rightFit),
    cross(bottomFit, leftFit),
  ];
  for (final p in quad) {
    // A fit landing well outside the rectangle it was derived from is a bad
    // fit, not a discovery.
    if (p == null ||
        p.dx < minX - w * 0.15 ||
        p.dx > maxX + w * 0.15 ||
        p.dy < minY - h * 0.15 ||
        p.dy > maxY + h * 0.15) {
      return rect.corners;
    }
  }
  return quad.map((p) => toWorld(p!)).toList();
}

/// Least-squares fit of [points], as `y = m*x + c` when [horizontal] and
/// `x = m*y + c` otherwise. Null when there's too little to fit.
({double m, double c})? _fitLine(
  List<Offset> points, {
  required bool horizontal,
}) {
  if (points.length < 3) return null;
  final n = points.length;
  var sx = 0.0, sy = 0.0, sxy = 0.0, sxx = 0.0;
  for (final p in points) {
    final x = horizontal ? p.dx : p.dy;
    final y = horizontal ? p.dy : p.dx;
    sx += x;
    sy += y;
    sxy += x * y;
    sxx += x * x;
  }
  final denom = n * sxx - sx * sx;
  if (denom.abs() < 1e-6) return null;
  final m = (n * sxy - sx * sy) / denom;
  return (m: m, c: (sy - m * sx) / n);
}

/// Pushes the corners outward from the centre, recovering the pixel the
/// erosion shaved off plus a hair of bleed, so a crop never clips the
/// card's own printed border.
List<Offset> _grow(List<Offset> corners, double by) {
  final c = corners.reduce((a, b) => a + b) / corners.length.toDouble();
  return corners.map((p) {
    final v = p - c;
    return v.distance < 1e-6 ? p : p + v / v.distance * by;
  }).toList();
}

/// Rotates the corner list so entry 0 is the card's own top-left and the
/// card's long axis becomes the crop's height — that's what makes a card
/// lying sideways in its pocket come out upright.
///
/// ponytail: a half turn is geometrically indistinguishable, so an
/// upside-down card still crops upside-down. Rotating it is one tap in the
/// existing photo editor from triage; deciding it automatically needs
/// content analysis (where the name band is), which belongs with the OCR
/// rather than here.
List<Offset> _orderForCard(List<Offset> quad) {
  final c = quad.reduce((a, b) => a + b) / 4.0;
  // atan2 runs from -pi, so sorting by angle about the centre puts the
  // up-and-left corner first — the top-left for any quad rotated less than
  // a quarter turn — and proceeds clockwise in screen coordinates.
  final sorted = List.of(quad)
    ..sort(
      (a, b) => math
          .atan2(a.dy - c.dy, a.dx - c.dx)
          .compareTo(math.atan2(b.dy - c.dy, b.dx - c.dx)),
    );
  final topEdge = (sorted[1] - sorted[0]).distance;
  final sideEdge = (sorted[3] - sorted[0]).distance;
  // Wider than tall: shift by one so the long edge becomes the height.
  if (topEdge > sideEdge) {
    return [sorted[1], sorted[2], sorted[3], sorted[0]];
  }
  return sorted;
}

/// Left-to-right, top-to-bottom — the order the cards sit on the page, so
/// review lines up with what the user is looking at. Rows are grouped by
/// relative gap rather than an absolute band, since a tilted page
/// staircases each row's centres.
List<CardQuad> _readingOrder(List<CardQuad> quads) {
  if (quads.length < 2) return quads;
  final heights = quads.map((q) => q.bounds.bottom - q.bounds.top).toList()
    ..sort();
  final rowGap = heights[heights.length ~/ 2] * 0.6;

  final byY = List.of(quads)
    ..sort((a, b) => a.center.dy.compareTo(b.center.dy));
  final rows = <List<CardQuad>>[];
  for (final q in byY) {
    if (rows.isEmpty || q.center.dy - rows.last.first.center.dy > rowGap) {
      rows.add([q]);
    } else {
      rows.last.add(q);
    }
  }
  final ordered = <CardQuad>[];
  for (final row in rows) {
    row.sort((a, b) => a.center.dx.compareTo(b.center.dx));
    ordered.addAll(row);
  }
  return ordered;
}

// ---------------------------------------------------------------------------
// Cropping
// ---------------------------------------------------------------------------

/// Warps one quad out of the full-resolution page into an upright,
/// card-aspect JPEG — the perspective-correction step. The output is
/// normalized to [_cardAspect] rather than to the quad's own measured shape
/// because `classifyCardText` reads fields by their position as a fraction
/// of the image and expects that image to be a card.
Uint8List _rectifyCard(img.Image page, CardQuad quad) {
  final c = quad.corners;
  final longSide = math.max(
    ((c[3] - c[0]).distance + (c[2] - c[1]).distance) / 2,
    1.0,
  );
  final height = longSide.round().clamp(1, _cardMaxHeight);
  final width = math.max(1, (height * _cardAspect).round());

  final out = img.copyRectify(
    page,
    topLeft: img.Point(c[0].dx, c[0].dy),
    topRight: img.Point(c[1].dx, c[1].dy),
    bottomRight: img.Point(c[2].dx, c[2].dy),
    bottomLeft: img.Point(c[3].dx, c[3].dy),
    interpolation: img.Interpolation.linear,
    // Without an explicit target, copyRectify writes into a copy the size
    // of the whole page — nine of those per page is how this runs out of
    // memory.
    toImage: img.Image(width: width, height: height),
  );
  return img.encodeJpg(out, quality: 90);
}

// ---------------------------------------------------------------------------
// I/O. Kept alongside the pure pipeline above the way live_framing.dart keeps
// cropToFraming next to captureFrameFraction.
// ---------------------------------------------------------------------------

/// Reads one binder-page image and runs the whole detect/crop pipeline on a
/// background isolate, so neither the decode nor the contour pass blocks the
/// UI thread. One page per call: the caller loops, which is what bounds how
/// many full-size bitmaps exist at once (one) no matter how many pages the
/// user picked.
Future<BinderPageScan> scanBinderPage(String path) async =>
    compute(detectCardsOnPage, await File(path).readAsBytes());

/// Moves the crops into permanent app storage — the same [PhotoStore] every
/// other card photo in the app lives in, so a crop that becomes a card needs
/// no copying or second location later.
Future<List<String>> saveCardCrops(List<Uint8List> jpgs) async {
  final dir = await getTemporaryDirectory();
  final paths = <String>[];
  for (final bytes in jpgs) {
    final temp = File(p.join(dir.path, '${const Uuid().v4()}.jpg'));
    await temp.writeAsBytes(bytes);
    paths.add(await PhotoStore.instance.save(temp));
    await temp.delete();
  }
  return paths;
}
