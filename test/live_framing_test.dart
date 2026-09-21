// Regression coverage for the live-camera capture frame's geometry: the
// fraction of the preview the on-screen frame occupies must always match
// the fraction `cropToFraming` keeps from the captured photo, or what the
// user sees live would stop matching what's saved (see live_framing.dart).

import 'package:flutter_test/flutter_test.dart';

import 'package:pokedex_tcg/screens/capture/live_framing.dart';

void main() {
  group('captureFrameFraction', () {
    test('preview wider than target trims left/right, keeps full height', () {
      final frame = captureFrameFraction(
        previewAspect: 4 / 3,
        targetAspect: kCardAspect,
      );
      expect(frame.height, 1.0);
      expect(frame.width, closeTo((5 / 7) / (4 / 3), 0.0001));
      expect(frame.width, lessThan(1.0));
    });

    test('preview narrower than target trims top/bottom, keeps full width', () {
      final frame = captureFrameFraction(
        previewAspect: 1 / 2,
        targetAspect: kCardAspect,
      );
      expect(frame.width, 1.0);
      expect(frame.height, closeTo((1 / 2) / (5 / 7), 0.0001));
      expect(frame.height, lessThan(1.0));
    });

    test('preview already at target aspect keeps the whole frame', () {
      final frame = captureFrameFraction(
        previewAspect: kCardAspect,
        targetAspect: kCardAspect,
      );
      expect(frame.width, 1.0);
      expect(frame.height, 1.0);
    });
  });
}
