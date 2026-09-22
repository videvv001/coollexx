// Regression coverage for OCR field classification. The bug this guards
// against: a card's lower portion holds the kind banner, the name, the
// trait line AND the card ID, so any rule shaped like "text near the
// bottom is the name" picks the wrong one — it previously reported
// "CHARACTER" (the kind banner) as the card's name.
//
// These exercise `classifyCardText` directly, with blocks laid out the way
// a real card stacks them, so they run without a device or ML Kit.

import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:pokedex_tcg/data/card_text_layout.dart';
import 'package:pokedex_tcg/models/card_language.dart';
import 'package:pokedex_tcg/models/release_category.dart';

/// A block spanning [top]..[bottom] vertically, centred horizontally
/// unless told otherwise — coordinates are fractions of the whole card.
OcrBlock block(
  String text, {
  required double top,
  required double bottom,
  double left = 0.2,
  double right = 0.8,
  int lineCount = 1,
  double? confidence,
}) {
  return OcrBlock(
    text: text,
    box: Rect.fromLTRB(left, top, right, bottom),
    lineCount: lineCount,
    confidence: confidence,
  );
}

/// The real stacking order on a One Piece character card: effect box,
/// then the kind banner, then the name, then the trait line, with the ID
/// stamped in the bottom-right corner.
List<OcrBlock> onePieceCard({
  required String kind,
  required String name,
  String trait = '白ひげ海賊団',
  String effect = 'このキャラのパワー+3000',
  String id = 'OP09-001',
}) {
  return [
    block(effect, top: 0.55, bottom: 0.74, left: 0.08, right: 0.92, lineCount: 3),
    block(kind, top: 0.78, bottom: 0.83),
    block(name, top: 0.84, bottom: 0.90),
    block(trait, top: 0.91, bottom: 0.94),
    block(id, top: 0.95, bottom: 0.99, left: 0.72, right: 0.95),
  ];
}

void main() {
  group('One Piece', () {
    test('classifies the kind/name/trait/effect stack', () {
      final guess = classifyCardText(
        onePieceCard(kind: 'CHARACTER', name: 'アトモス'),
        ReleaseCategory.onePiece,
      );

      expect(guess.name, 'アトモス');
      expect(guess.kind, 'Character');
      expect(guess.number, 'OP09-001');
      expect(guess.language, CardLanguage.jp);
    });

    test('never reports a kind banner as the name', () {
      // Every kind the app knows about, each with a Japanese name below it.
      const cases = {
        'CHARACTER': 'Character',
        'LEADER': 'Leader',
        'EVENT': 'Event',
        'STAGE': 'Stage',
      };
      for (final entry in cases.entries) {
        final guess = classifyCardText(
          onePieceCard(kind: entry.key, name: 'アトモス'),
          ReleaseCategory.onePiece,
        );
        expect(guess.kind, entry.value, reason: entry.key);
        expect(guess.name, 'アトモス', reason: entry.key);
        expect(guess.name, isNot(equalsIgnoringCase(entry.key)));
      }
    });

    test('picks the name over the trait line directly beneath it', () {
      final guess = classifyCardText(
        onePieceCard(kind: 'CHARACTER', name: 'ゾロ', trait: '麦わらの一味'),
        ReleaseCategory.onePiece,
      );
      expect(guess.name, 'ゾロ');
    });

    test('ignores effect text even when it sits below the kind banner', () {
      // Same card, but OCR returned the effect box lower than usual — the
      // name must still win over prose that happens to be nearer.
      final guess = classifyCardText([
        block('CHARACTER', top: 0.70, bottom: 0.75),
        block(
          'このキャラが登場した時、相手のキャラ1枚までを手札に戻す。',
          top: 0.76,
          bottom: 0.84,
          left: 0.08,
          right: 0.92,
          lineCount: 2,
        ),
        block('アトモス', top: 0.86, bottom: 0.91),
      ], ReleaseCategory.onePiece);

      expect(guess.name, 'アトモス');
    });

    test('reads an English print the same way', () {
      final guess = classifyCardText(
        onePieceCard(
          kind: 'CHARACTER',
          name: 'Atmos',
          trait: 'Whitebeard Pirates',
          effect: 'This character gains +1000 power.',
        ),
        ReleaseCategory.onePiece,
      );
      expect(guess.name, 'Atmos');
      expect(guess.kind, 'Character');
      expect(guess.language, CardLanguage.eng);
    });

    test('collapses the duplicate block the second script pass produces', () {
      // Latin and Japanese recognition both report the name line; the
      // Latin pass mangles it. The CJK reading should win, and the pair
      // must not be treated as name-then-trait.
      final guess = classifyCardText([
        block('CHARACTER', top: 0.78, bottom: 0.83),
        block('7 hEX', top: 0.84, bottom: 0.90),
        block('アトモス', top: 0.84, bottom: 0.90),
        block('白ひげ海賊団', top: 0.91, bottom: 0.94),
      ], ReleaseCategory.onePiece);

      expect(guess.name, 'アトモス');
    });

    test('returns no name rather than guessing when nothing qualifies', () {
      final guess = classifyCardText([
        block('CHARACTER', top: 0.78, bottom: 0.83),
        block(
          'このキャラのパワー+3000、このキャラは相手のキャラを攻撃できる。',
          top: 0.55,
          bottom: 0.74,
          lineCount: 3,
        ),
      ], ReleaseCategory.onePiece);

      expect(guess.name, isNull);
      expect(guess.kind, 'Character');
    });
  });

  group('Pokémon', () {
    // Name top-left printed large, HP top-right, evolution tag above the
    // name, set number bottom-left.
    List<OcrBlock> pokemonCard({required String name}) => [
      block('1進化', top: 0.02, bottom: 0.05, left: 0.04, right: 0.16),
      block(name, top: 0.04, bottom: 0.10, left: 0.18, right: 0.60),
      block('HP 100', top: 0.04, bottom: 0.09, left: 0.72, right: 0.94),
      block(
        'コインを2回投げ、オモテの数×70ダメージ。',
        top: 0.62,
        bottom: 0.70,
        left: 0.08,
        right: 0.92,
        lineCount: 2,
      ),
      block('051/076', top: 0.95, bottom: 0.98, left: 0.10, right: 0.30),
    ];

    test('reads the name and set number', () {
      final guess = classifyCardText(
        pokemonCard(name: 'ジャランゴ'),
        ReleaseCategory.pokemon,
      );
      expect(guess.name, 'ジャランゴ');
      expect(guess.number, '051/076');
      expect(guess.language, CardLanguage.jp);
    });

    test('strips HP when OCR merges it into the name line', () {
      final guess = classifyCardText([
        block('ジャランゴ HP 100', top: 0.04, bottom: 0.10, left: 0.18, right: 0.66),
        block('051/076', top: 0.95, bottom: 0.98, left: 0.10, right: 0.30),
      ], ReleaseCategory.pokemon);

      expect(guess.name, 'ジャランゴ');
    });

    test('does not mistake the evolution tag for the name', () {
      final guess = classifyCardText(
        pokemonCard(name: 'ピカチュウ'),
        ReleaseCategory.pokemon,
      );
      expect(guess.name, isNot('1進化'));
    });
  });

  test('Others never reports a kind, since no kind list applies to it', () {
    // Callers skip OCR for Others entirely; this just pins down that the
    // One Piece kind vocabulary doesn't leak into other games.
    final guess = classifyCardText([
      block('CHARACTER', top: 0.80, bottom: 0.86),
    ], ReleaseCategory.others);
    expect(guess.kind, isNull);
  });
}
