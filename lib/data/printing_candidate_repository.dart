import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/printing_candidate.dart';
import '../pricing/price_research_service.dart';
import 'app_database.dart';

/// Cache of the known printings of a logical card (game + number + language),
/// as found by printing research. One row per logical card, replaced when
/// research is repeated; a row older than the caller's `maxAge` is ignored so
/// a newly released printing is eventually picked up.
class PrintingCandidateRepository {
  PrintingCandidateRepository({Database Function()? dbOverride})
    : _dbOverride = dbOverride;

  final Database Function()? _dbOverride;

  Future<Database> get _db async =>
      _dbOverride != null ? _dbOverride() : AppDatabase.instance.database;

  String _key(PrintingDescriptor p) =>
      '${p.game.code}|${p.cardNumber.trim().toUpperCase()}|'
      '${p.language.trim().toLowerCase()}';

  /// Fresh cached printings, or null when there are none (or they're stale).
  Future<List<PrintingCandidate>?> lookup(
    PrintingDescriptor logical, {
    required Duration maxAge,
    DateTime? now,
  }) async {
    final rows = await (await _db).query(
      'printing_candidates',
      where: 'id = ?',
      whereArgs: [_key(logical)],
    );
    if (rows.isEmpty) return null;
    final at = DateTime.tryParse(rows.single['researchedAt'] as String);
    if (at == null || (now ?? DateTime.now()).difference(at) > maxAge) {
      return null;
    }
    try {
      return [
        for (final c in jsonDecode(rows.single['candidates'] as String) as List)
          PrintingCandidate.fromJson(c as Map<String, dynamic>),
      ];
    } catch (_) {
      return null; // unreadable row: research again
    }
  }

  Future<void> save(
    PrintingDescriptor logical,
    List<PrintingCandidate> candidates, {
    String? provider,
    DateTime? now,
  }) async {
    await (await _db).insert('printing_candidates', {
      'id': _key(logical),
      'game': logical.game.code,
      'cardNumber': logical.cardNumber.trim().toUpperCase(),
      'language': logical.language.trim().toLowerCase(),
      'candidates': jsonEncode([for (final c in candidates) c.toJson()]),
      'researchedAt': (now ?? DateTime.now()).toIso8601String(),
      'provider': provider,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
