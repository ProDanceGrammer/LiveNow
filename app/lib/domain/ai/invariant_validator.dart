import '../../data/database.dart';
import '../budget_rules.dart';
import 'dedupe_service.dart';
import 'price_planner.dart';

/// Machine-readable error codes (spec section 7), returned to the model/UI.
class ValidationCode {
  static const aggregateTarget = 'ERR_AGGREGATE_TARGET'; // I1
  static const sumMismatch = 'ERR_SUM_MISMATCH'; // I2
  static const badQuantity = 'ERR_BAD_QUANTITY'; // I3
  static const missingRate = 'ERR_MISSING_RATE'; // I3
  static const missingCategory = 'ERR_MISSING_CATEGORY'; // I3
  static const accountIncompatible = 'ERR_ACCOUNT_INCOMPATIBLE'; // I4
  static const duplicate = 'ERR_DUPLICATE'; // I6
  static const needsConfirmation = 'NEEDS_CONFIRMATION'; // I7
}

class ValidationIssue {
  const ValidationIssue(
    this.code,
    this.message, {
    this.index,
    this.details = const {},
  });

  final String code;
  final String message;

  /// Index of the offending transaction / operation in the batch, if any.
  final int? index;
  final Map<String, Object?> details;

  Map<String, Object?> toJson() => {
    'code': code,
    'message': message,
    'index': ?index,
    if (details.isNotEmpty) 'details': details,
  };
}

/// A category the batch creates. [id] is a temporary id other items of the
/// batch may use as a parent or a transaction target.
class PlannedCategory {
  const PlannedCategory({
    required this.id,
    this.parentId,
    this.accountCountId,
    this.accountUseId,
  });

  final String id;
  final String? parentId;
  final String? accountCountId;
  final String? accountUseId;
}

/// An existing (or planned) category that changes parent (the C5 wrapper).
class PlannedMove {
  const PlannedMove(this.categoryId, this.newParentId);
  final String categoryId;
  final String? newParentId;
}

/// A transaction the batch would create. [amount] is the money value.
class PlannedTransaction {
  const PlannedTransaction({
    required this.name,
    required this.categoryId,
    required this.quantity,
    required this.amount,
    required this.date,
    this.rateCount,
    this.rateInteract,
    this.isIncome = false,
    this.isTransfer = false,
    this.accountCountId,
    this.accountUseId,
    this.checkDuplicate = true,
  });

  final String name;

  /// An existing category id, or a [PlannedCategory.id]; null = missing.
  final String? categoryId;
  final double quantity;
  final double amount;
  final DateTime date;
  final double? rateCount;
  final double? rateInteract;
  final bool isIncome;
  final bool isTransfer;

  /// How it was paid (null = unconstrained), checked against the category (I4).
  final String? accountCountId;
  final String? accountUseId;

  /// Skip the I6 lookup (e.g. after the user said "add it anyway").
  final bool checkDuplicate;
}

/// An operation that removes or overwrites data (I7).
class PlannedDestructiveOp {
  const PlannedDestructiveOp(this.description, {this.confirmed = false});
  final String description;
  final bool confirmed;
}

class ValidationResult {
  const ValidationResult({this.errors = const [], this.confirmations = const []});

  /// Blocks the commit.
  final List<ValidationIssue> errors;

  /// I7: operations waiting for an explicit "yes" from the user.
  final List<ValidationIssue> confirmations;

  bool get ok => errors.isEmpty;
  bool get canCommit => errors.isEmpty && confirmations.isEmpty;

  Map<String, Object?> toJson() => {
    'ok': ok,
    'errors': [for (final e in errors) e.toJson()],
    'confirmations': [for (final e in confirmations) e.toJson()],
  };
}

/// I1-I4, I6, I7 over a proposed batch. Reads the category tree and the
/// transactions; writes nothing.
class InvariantValidator {
  InvariantValidator(this.db, {DedupeService? dedupe})
    : dedupe = dedupe ?? DedupeService(db);

  final AppDatabase db;
  final DedupeService dedupe;

  /// I2 tolerance (receipt rounding).
  static const double sumTolerance = 0.02;

  Future<ValidationResult> validate({
    required List<PlannedTransaction> transactions,
    List<PlannedCategory> newCategories = const [],
    List<PlannedMove> moves = const [],
    List<PlannedDestructiveOp> destructiveOps = const [],

    /// I2: the receipt total the amounts must add up to (null = not checked).
    /// Pass transactions of the user's own tender, discounts already netted.
    double? expectedTotal,
  }) async {
    final cats = await db.select(db.budgetCategoriesTable).get();
    final parentOf = <String, String?>{for (final c in cats) c.id: c.parentId};
    final accounts = <String, ({String? count, String? use})>{
      for (final c in cats) c.id: (count: c.accountCountId, use: c.accountUseId),
    };
    for (final c in newCategories) {
      parentOf[c.id] = c.parentId;
      accounts[c.id] = (count: c.accountCountId, use: c.accountUseId);
    }
    for (final m in moves) {
      parentOf[m.categoryId] = m.newParentId;
    }
    final hasChildren = {...parentOf.values.nonNulls};

    final errors = <ValidationIssue>[];
    var sum = 0.0;
    for (var i = 0; i < transactions.length; i++) {
      final t = transactions[i];
      sum += t.isIncome ? -t.amount : t.amount;

      // I3: category, quantity, rates.
      final cid = t.categoryId;
      if (cid == null || !parentOf.containsKey(cid)) {
        errors.add(
          ValidationIssue(
            ValidationCode.missingCategory,
            '"${t.name}" has no existing category.',
            index: i,
          ),
        );
      } else {
        // I1
        if (hasChildren.contains(cid)) {
          errors.add(
            ValidationIssue(
              ValidationCode.aggregateTarget,
              '"${t.name}" targets a category with sub-categories.',
              index: i,
              details: {'category_id': cid},
            ),
          );
        } else {
          // I4
          final a = accounts[cid]!;
          if (!accountsCompatible(
            leafCount: a.count,
            leafUse: a.use,
            wantCount: t.accountCountId,
            wantUse: t.accountUseId,
          )) {
            errors.add(
              ValidationIssue(
                ValidationCode.accountIncompatible,
                '"${t.name}": the category accounts do not match how it was paid.',
                index: i,
                details: {'category_id': cid},
              ),
            );
          }
        }
      }
      final q = t.quantity;
      final badQuantity =
          q.isNaN ||
          q.isInfinite ||
          q == 0 ||
          (q < 0 && !t.isIncome && !t.isTransfer) ||
          t.amount.isNaN ||
          t.amount.isInfinite;
      if (badQuantity) {
        errors.add(
          ValidationIssue(
            ValidationCode.badQuantity,
            '"${t.name}": quantity must be a positive number.',
            index: i,
            details: {'quantity': q},
          ),
        );
      }
      bool ok(double? r) => r != null && r > 0 && !r.isNaN && !r.isInfinite;
      if (!ok(t.rateCount) || !ok(t.rateInteract)) {
        errors.add(
          ValidationIssue(
            ValidationCode.missingRate,
            '"${t.name}": both exchange rates are required.',
            index: i,
          ),
        );
      }

      // I6
      if (t.checkDuplicate && !t.amount.isNaN) {
        final dups = await dedupe.findDuplicates(
          date: t.date,
          amount: t.amount,
          text: t.name,
        );
        if (dups.isNotEmpty) {
          errors.add(
            ValidationIssue(
              ValidationCode.duplicate,
              '"${t.name}" looks like an existing transaction.',
              index: i,
              details: {
                'transaction_ids': [for (final d in dups) d.transactionId],
              },
            ),
          );
        }
      }
    }

    // I2
    if (expectedTotal != null &&
        (round2(sum) - expectedTotal).abs() > sumTolerance + 1e-9) {
      errors.add(
        ValidationIssue(
          ValidationCode.sumMismatch,
          'The lines add up to ${round2(sum)}, the receipt says $expectedTotal.',
          details: {
            'sum': round2(sum),
            'expected': expectedTotal,
            'difference': round2(sum - expectedTotal),
          },
        ),
      );
    }

    // I7
    final confirmations = <ValidationIssue>[];
    for (var i = 0; i < destructiveOps.length; i++) {
      final op = destructiveOps[i];
      if (op.confirmed) continue;
      confirmations.add(
        ValidationIssue(
          ValidationCode.needsConfirmation,
          'Needs explicit confirmation: ${op.description}',
          index: i,
        ),
      );
    }
    return ValidationResult(errors: errors, confirmations: confirmations);
  }
}
