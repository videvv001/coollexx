// Smoke test: the app boots against a real (temp, file-backed) SQLite
// database via sqflite_common_ffi, with path_provider faked to point at a
// temp directory. No mocked-out data layer — this exercises the same
// AppState.load() / repository path the real app uses.
//
// AppState.load() and the screens' own repository queries do real file
// I/O, which Flutter's fake-async test clock never advances on its own —
// that part needs tester.runAsync(). But calling tester.pump() *inside*
// runAsync doesn't drive a real frame either (the fake clock runAsync
// suspends is what pump() needs), so the pattern here is: runAsync only to
// let real I/O land, then pump() outside it to let the tree rebuild.
// pumpAndSettle() is avoided entirely — screens like Trade show an
// indeterminate CircularProgressIndicator while their own FutureBuilder is
// in flight, and an indeterminate spinner's animation never "settles".

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pokedex_tcg/main.dart';

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.dir);

  final Directory dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir.path;

  @override
  Future<String?> getApplicationSupportPath() async => dir.path;

  @override
  Future<String?> getTemporaryPath() async => dir.path;
}

/// Waits for [finder] to find something, alternating a real-time delay
/// (inside runAsync, so pending file/database I/O can actually complete)
/// with a plain pump (outside runAsync, so the tree rebuilds to reflect it).
Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('Timed out waiting for $finder');
    }
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // The isolate-backed factory relies on cross-isolate messaging, which
    // adds another real-async dependency on top of the fake-zone issue
    // above; the no-isolate factory keeps everything on one isolate.
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pokedex_tcg_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  testWidgets('boots to the first-run empty state with no data', (
    tester,
  ) async {
    await tester.pumpWidget(const PokedexTcgApp());
    await _pumpUntilFound(tester, find.text('Start with one card'));

    expect(find.text('My collection'), findsOneWidget);
    expect(find.text('Scan a card'), findsOneWidget);
  });

  testWidgets('bottom tab bar switches between the four tabs', (tester) async {
    await tester.pumpWidget(const PokedexTcgApp());
    await _pumpUntilFound(tester, find.text('Start with one card'));

    await tester.tap(find.text('Sets'));
    await tester.pump();
    await _pumpUntilFound(tester, find.text('No releases yet'));

    await tester.tap(find.text('Trade'));
    await tester.pump();
    await _pumpUntilFound(tester, find.text('No cards marked for trade'));

    await tester.tap(find.text('Me'));
    await tester.pump();
    await _pumpUntilFound(
      tester,
      find.text('Everything is stored on this phone'),
    );
  });
}
