import 'package:drift/drift.dart' show Variable;

import '../../data/database.dart';
import 'ai_alias_db_source.dart';
import 'alias_source.dart';

/// A receipt that was confirmed before: the batch that holds its rows and what
/// was saved, so the user can see it before deciding what to do with a second copy.
class SeenReceipt {
  const SeenReceipt({
    required this.batchId,
    required this.jobId,
    required this.at,
    required this.merchant,
    required this.lines,
  });

  final String batchId;
  final String jobId;
  final DateTime? at;
  final String? merchant;
  final List<SeenLine> lines;

  Map<String, dynamic> toJson() => {
    'batch_id': batchId,
    'job_id': jobId,
    'at': at?.toUtc().toIso8601String(),
    'merchant': merchant,
    'lines': [for (final l in lines) l.toJson()],
  };

  factory SeenReceipt.fromJson(Map<String, dynamic> j) => SeenReceipt(
    batchId: (j['batch_id'] ?? '').toString(),
    jobId: (j['job_id'] ?? '').toString(),
    at: DateTime.tryParse((j['at'] ?? '').toString())?.toUtc(),
    merchant: j['merchant']?.toString(),
    lines: [
      if (j['lines'] is List)
        for (final l in j['lines'] as List)
          if (l is Map) SeenLine.fromJson(Map<String, dynamic>.from(l)),
    ],
  );
}

class SeenLine {
  const SeenLine({
    required this.name,
    required this.category,
    required this.quantity,
    required this.unitPrice,
  });

  final String name;
  final String? category;
  final double quantity;
  final double unitPrice;

  double get amount => quantity * unitPrice;

  Map<String, dynamic> toJson() => {
    'name': name,
    'category': category,
    'quantity': quantity,
    'unit_price': unitPrice,
  };

  factory SeenLine.fromJson(Map<String, dynamic> j) => SeenLine(
    name: (j['name'] ?? '').toString(),
    category: j['category']?.toString(),
    quantity: (j['quantity'] as num?)?.toDouble() ?? 0,
    unitPrice: (j['unit_price'] as num?)?.toDouble() ?? 0,
  );
}

/// Which receipts were already confirmed. Two keys per receipt in
/// `ai_rules_memory` (synced): the photo's hash and a fingerprint of what was
/// read (shop, minute, total). A hit counts only while its batch is not undone.
class ReceiptMemory {
  ReceiptMemory(this.db, this.rules);

  final AppDatabase db;
  final AiRulesMemory rules;

  static String shaKey(String sha) => 'receipt.sha.$sha';
  static String fpKey(String fp) => 'receipt.fp.$fp';

  /// Shop + minute + total; null when the time or the total was not read.
  static String? fingerprint({
    required String? merchant,
    required DateTime? at,
    required double? total,
  }) {
    if (at == null || total == null || !(total > 0)) return null;
    final u = at.toUtc();
    String p(int v, [int w = 2]) => v.toString().padLeft(w, '0');
    final minute = '${p(u.year, 4)}${p(u.month)}${p(u.day)}${p(u.hour)}${p(u.minute)}';
    return '${normalizeReceiptText(merchant ?? '')}|$minute|${total.toStringAsFixed(2)}';
  }

  Future<void> remember({
    String? sha,
    String? fp,
    required String jobId,
    required String batchId,
  }) async {
    final value = {'job_id': jobId, 'batch_id': batchId};
    if (sha != null && sha.isNotEmpty) await rules.set(shaKey(sha), value);
    if (fp != null && fp.isNotEmpty) await rules.set(fpKey(fp), value);
  }

  /// The earlier confirmed receipt with this photo or content, or null. A batch of
  /// [jobId] itself (a rebuild of the same job) is never "earlier".
  Future<SeenReceipt?> find({
    String? sha,
    String? fp,
    required String jobId,
  }) async {
    for (final key in [
      if (sha != null && sha.isNotEmpty) shaKey(sha),
      if (fp != null && fp.isNotEmpty) fpKey(fp),
    ]) {
      final v = await rules.get(key);
      final batchId = v?['batch_id']?.toString();
      if (batchId == null || v?['job_id']?.toString() == jobId) continue;
      final seen = await _load(batchId, v!['job_id']?.toString() ?? '');
      if (seen != null) return seen;
    }
    return null;
  }

  Future<SeenReceipt?> _load(String batchId, String jobId) async {
    final batch = await (db.select(db.aiBatchesTable)..where((t) => t.id.equals(batchId))).getSingleOrNull();
    if (batch == null || batch.undoneAt != null) return null;
    final rows = await db.customSelect(
      'SELECT t.name AS name, t.quantity AS quantity, t.unit_price AS unit_price, '
      't.occurred_at AS occurred_at, c.name AS category '
      'FROM ai_batch_items i '
      'JOIN budget_transactions t ON t.id = i.entity_id '
      'LEFT JOIN budget_categories c ON c.id = t.category_id '
      "WHERE i.batch_id = ? AND i.entity_type = 'transaction' ORDER BY i.position",
      variables: [Variable.withString(batchId)],
    ).get();
    if (rows.isEmpty) return null;
    return SeenReceipt(
      batchId: batchId,
      jobId: jobId,
      at: DateTime.tryParse(rows.first.read<String>('occurred_at'))?.toUtc(),
      merchant: batch.summary.startsWith('Чек ') ? batch.summary.substring(4) : null,
      lines: [
        for (final r in rows)
          SeenLine(
            name: r.read<String>('name'),
            category: r.read<String?>('category'),
            quantity: r.read<double>('quantity'),
            unitPrice: r.read<double>('unit_price'),
          ),
      ],
    );
  }
}
