import 'package:drift/drift.dart' show Variable;

import '../../core/time_codec.dart';
import '../../data/database.dart';
import 'alias_source.dart';

/// An existing transaction that looks like the one about to be added.
class DuplicateCandidate {
  const DuplicateCandidate({
    required this.transactionId,
    required this.name,
    required this.categoryId,
    required this.amount,
    required this.date,
  });

  final String transactionId;
  final String name;
  final String? categoryId;
  final double amount;

  /// The effective date: the linked action's start, else `occurred_at`.
  final DateTime date;
}

/// I6: before inserting, look for a transaction with the same date (+-1 day),
/// a similar name and an equal amount (a real case: one receipt was sent
/// twice). Read-only: the caller asks the user instead of inserting.
class DedupeService {
  DedupeService(this.db);

  final AppDatabase db;

  /// Amounts within this are equal.
  static const double amountTolerance = 0.011;

  /// [amount] is the money value (quantity x price, or the quantity of an
  /// amount category). [text] is the line name or merchant; null/blank skips
  /// the name test (date + amount decide).
  Future<List<DuplicateCandidate>> findDuplicates({
    required DateTime date,
    required double amount,
    String? text,
  }) async {
    final from = dateTimeToDb(date.toUtc().subtract(const Duration(days: 1)))!;
    final to = dateTimeToDb(date.toUtc().add(const Duration(days: 1)))!;
    final rows = await db
        .customSelect(
          'SELECT t.id AS id, t.name AS name, t.category_id AS category_id, '
          't.quantity AS quantity, t.unit_price AS unit_price, '
          't.is_amount AS is_amount, '
          'COALESCE(a.start_at, t.occurred_at) AS eff '
          'FROM budget_transactions t '
          'LEFT JOIN actions a ON a.id = t.action_id '
          'WHERE COALESCE(a.start_at, t.occurred_at) >= ? '
          'AND COALESCE(a.start_at, t.occurred_at) <= ?',
          variables: [Variable.withString(from), Variable.withString(to)],
        )
        .get();
    final found = <DuplicateCandidate>[];
    for (final r in rows) {
      final quantity = r.read<double>('quantity');
      final amountOf = r.read<bool>('is_amount')
          ? quantity
          : r.read<double>('unit_price') * quantity;
      if ((amountOf - amount).abs() > amountTolerance) continue;
      final name = r.read<String>('name');
      if (!namesSimilar(name, text)) continue;
      found.add(
        DuplicateCandidate(
          transactionId: r.read<String>('id'),
          name: name,
          categoryId: r.read<String?>('category_id'),
          amount: amountOf,
          date: dateTimeFromDb(r.read<String>('eff'))!,
        ),
      );
    }
    return found;
  }

  /// Same text, or one contains the other, or at least half of the words are
  /// shared. A blank side counts as "unknown" = similar.
  static bool namesSimilar(String? a, String? b) {
    final x = normalizeReceiptText(a ?? '');
    final y = normalizeReceiptText(b ?? '');
    if (x.isEmpty || y.isEmpty) return true;
    if (x.contains(y) || y.contains(x)) return true;
    final split = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
    final tx = x.split(split).where((t) => t.isNotEmpty).toSet();
    final ty = y.split(split).where((t) => t.isNotEmpty).toSet();
    if (tx.isEmpty || ty.isEmpty) return true;
    final shared = tx.intersection(ty).length;
    return shared / tx.union(ty).length >= 0.5;
  }
}
