import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/ids.dart';
import '../../core/time_codec.dart';
import '../../data/database.dart';
import 'alias_source.dart';

/// Alias memory over `product_aliases` (what the user taught the assistant:
/// receipt text -> category, unit override, typical weight). Keys are
/// [normalizeReceiptText] of the printed name; the row id is derived from the
/// key, so two devices that learn the same thing converge on one row.
class DbAliasSource implements AliasSource {
  DbAliasSource(this.db);

  final AppDatabase db;

  static String idFor(String normalizedKey) => deriveId('ai-alias', normalizedKey);

  Future<ProductAlias?> row(String receiptText) =>
      (db.select(db.productAliasesTable)..where(
            (t) => t.pattern.equals(normalizeReceiptText(receiptText)),
          ))
          .getSingleOrNull();

  /// Only an alias that names a category is a category alias.
  @override
  Future<AliasEntry?> lookup(String normalizedReceiptText) async {
    final r = await (db.select(
      db.productAliasesTable,
    )..where((t) => t.pattern.equals(normalizedReceiptText))).getSingleOrNull();
    final cat = r?.categoryId;
    if (r == null || cat == null) return null;
    return AliasEntry(
      categoryId: cat,
      unitOverride: r.unitOverride,
      weightGramsDefault: r.weightGramsDefault,
      pieceDefault: r.pieceDefault?.round(),
      source: r.source,
    );
  }

  /// Normalised keys of every product the user said counts by the piece.
  Future<Set<String>> pieceOnlyKeys() async {
    final rows = await (db.select(
      db.productAliasesTable,
    )..where((t) => t.unitOverride.equals('piece'))).get();
    return {for (final r in rows) r.pattern};
  }

  /// Typical weight (grams) of one pack of every product that has one.
  Future<Map<String, double>> weightDefaults() async {
    final rows = await (db.select(
      db.productAliasesTable,
    )..where((t) => t.weightGramsDefault.isNotNull())).get();
    return {for (final r in rows) r.pattern: r.weightGramsDefault!};
  }

  /// Learns (or updates) the alias of [receiptText]. Only the given fields
  /// change; the others of an existing row are kept.
  Future<void> remember(
    String receiptText, {
    String? categoryId,
    String? unitOverride,
    double? weightGramsDefault,
    String source = 'user',
  }) async {
    final key = normalizeReceiptText(receiptText);
    if (key.isEmpty) return;
    final id = idFor(key);
    final now = dateTimeToDb(DateTime.now())!;
    final existing = await (db.select(
      db.productAliasesTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing == null) {
      await db.into(db.productAliasesTable).insert(
            ProductAliasesTableCompanion.insert(
              id: id,
              pattern: key,
              categoryId: Value(categoryId),
              unitOverride: Value(unitOverride),
              weightGramsDefault: Value(weightGramsDefault),
              source: Value(source),
              createdAt: now,
              updatedAt: now,
            ),
          );
      return;
    }
    await (db.update(db.productAliasesTable)..where((t) => t.id.equals(id))).write(
      ProductAliasesTableCompanion(
        categoryId: categoryId == null ? const Value.absent() : Value(categoryId),
        unitOverride: unitOverride == null
            ? const Value.absent()
            : Value(unitOverride),
        weightGramsDefault: weightGramsDefault == null
            ? const Value.absent()
            : Value(weightGramsDefault),
        source: Value(source),
        updatedAt: Value(now),
      ),
    );
  }
}

/// `ai_rules_memory`: small named rules (`card.6141` -> `{"account_id": ...}`,
/// `cash.TRY`, free-text user rules). One row per key (derived id).
class AiRulesMemory {
  AiRulesMemory(this.db);

  final AppDatabase db;

  static String idFor(String key) => deriveId('ai-rule', key);

  Future<Map<String, dynamic>?> get(String key) async {
    final r = await (db.select(
      db.aiRulesMemoryTable,
    )..where((t) => t.id.equals(idFor(key)))).getSingleOrNull();
    return r == null ? null : _decode(r.valueJson);
  }

  /// Every rule whose key starts with [prefix], by key.
  Future<Map<String, Map<String, dynamic>>> withPrefix(String prefix) async {
    final rows = await db.select(db.aiRulesMemoryTable).get();
    return {
      for (final r in rows)
        if (r.key.startsWith(prefix)) r.key: _decode(r.valueJson),
    };
  }

  Future<void> set(
    String key,
    Map<String, dynamic> value, {
    String? sourceMessageId,
  }) async {
    final id = idFor(key);
    final now = dateTimeToDb(DateTime.now())!;
    final existing = await (db.select(
      db.aiRulesMemoryTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing == null) {
      await db.into(db.aiRulesMemoryTable).insert(
            AiRulesMemoryTableCompanion.insert(
              id: id,
              key: key,
              valueJson: Value(jsonEncode(value)),
              sourceMessageId: Value(sourceMessageId),
              createdAt: now,
              updatedAt: now,
            ),
          );
      return;
    }
    await (db.update(db.aiRulesMemoryTable)..where((t) => t.id.equals(id))).write(
      AiRulesMemoryTableCompanion(
        valueJson: Value(jsonEncode(value)),
        sourceMessageId: Value(sourceMessageId),
        updatedAt: Value(now),
      ),
    );
  }

  static Map<String, dynamic> _decode(String json) {
    try {
      final j = jsonDecode(json);
      if (j is Map) return Map<String, dynamic>.from(j);
    } catch (_) {}
    return {};
  }
}
