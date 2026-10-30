import 'package:drift/drift.dart' show OrderingTerm;

import '../../core/data_exceptions.dart';
import '../../data/database.dart';
import '../budget_rules.dart';
import '../budget_service.dart';
import 'alias_source.dart';

/// What to do with a product whose price (or payment method) differs from the
/// categories we have.
enum PlanKind {
  /// C4: an existing leaf already has this price and compatible accounts.
  reuseLeaf,

  /// C6: add a leaf under the product's existing aggregate.
  addLeaf,

  /// C5: create an empty same-name aggregate, move the old leaf under it, add
  /// the new leaf.
  wrapper,

  /// C7: a new named one-off leaf (unit piece) under a group.
  oneOffLeaf,
}

enum PlanReason { samePrice, priceChanged, accountsIncompatible, oneOff }

/// What [PricePlanner.plan] was asked, kept so [PricePlanner.apply] can
/// re-evaluate against the current data.
class PlanRequest {
  const PlanRequest({
    required this.categoryId,
    required this.newPrice,
    this.accountCountId,
    this.accountUseId,
    this.oneOffName,
  });

  /// The product's category (leaf or aggregate), or the GROUP for a one-off.
  final String categoryId;
  final double newPrice;

  /// How it was paid; null = no constraint (see [accountsCompatible]).
  final String? accountCountId;
  final String? accountUseId;

  /// Set for a C7 one-off item.
  final String? oneOffName;
}

/// A typed, write-free plan. [leafId] is the category the transaction goes
/// onto when it already exists (reuseLeaf); otherwise [newLeaf] describes the
/// leaf to create.
class PricePlan {
  const PricePlan({
    required this.kind,
    required this.reason,
    required this.request,
    this.leafId,
    this.aggregateId,
    this.oldLeafId,
    this.wrapper,
    this.newLeaf,
  });

  final PlanKind kind;
  final PlanReason reason;
  final PlanRequest request;

  /// reuseLeaf: the leaf to use.
  final String? leafId;

  /// addLeaf: the existing aggregate the new leaf goes under.
  final String? aggregateId;

  /// wrapper: the leaf that moves under the new aggregate.
  final String? oldLeafId;

  /// wrapper: the aggregate to create (parent = the old leaf's parent).
  final CategoryInput? wrapper;

  /// addLeaf / wrapper / oneOffLeaf: the leaf to create. Its parent is set for
  /// addLeaf and oneOffLeaf; for wrapper it is the new aggregate (filled in at
  /// apply time).
  final CategoryInput? newLeaf;

  bool get createsCategories => kind != PlanKind.reuseLeaf;
}

class AppliedPlan {
  const AppliedPlan({
    required this.leafId,
    this.createdIds = const [],
    this.movedIds = const [],
  });

  /// Attach the transaction to this leaf.
  final String leafId;

  /// Categories created, in creation order (wrapper first).
  final List<String> createdIds;

  /// Categories reparented.
  final List<String> movedIds;
}

/// C4-C7: plans (and applies) the category changes a price needs. Built on
/// [BudgetService.saveCategory] / [moveCategory], so the cycle and leaf-only
/// rules still hold.
class PricePlanner {
  PricePlanner(this.db, [BudgetService? budget])
    : budget = budget ?? BudgetService(db);

  final AppDatabase db;
  final BudgetService budget;

  static bool _samePrice(double? a, double b) =>
      a != null && (a - b).abs() < 0.005;

  /// Plans the change for product [categoryId] now costing [newPrice].
  /// Reads only. Cases:
  /// - a leaf of the product has this price and compatible accounts -> reuse;
  /// - the product is (or sits in a same-name) aggregate -> add a leaf;
  /// - a simple leaf -> wrapper; the new leaf takes the wanted accounts.
  Future<PricePlan> plan({
    required String categoryId,
    required double newPrice,
    String? accountCountId,
    String? accountUseId,
  }) async {
    if (!(newPrice > 0) || newPrice.isInfinite) {
      throw ArgumentError.value(newPrice, 'newPrice', 'must be positive');
    }
    final request = PlanRequest(
      categoryId: categoryId,
      newPrice: newPrice,
      accountCountId: accountCountId,
      accountUseId: accountUseId,
    );
    final all = await db.select(db.budgetCategoriesTable).get();
    final byId = {for (final c in all) c.id: c};
    final children = <String, List<BudgetCategory>>{};
    for (final c in all) {
      final p = c.parentId;
      if (p != null && byId.containsKey(p)) (children[p] ??= []).add(c);
    }
    final cat = byId[categoryId];
    if (cat == null) {
      throw const MissingRowException('That category no longer exists.');
    }

    bool compatible(BudgetCategory leaf) => accountsCompatible(
      leafCount: leaf.accountCountId,
      leafUse: leaf.accountUseId,
      wantCount: accountCountId,
      wantUse: accountUseId,
    );

    // A leaf of a same-name wrapper stands for the wrapper.
    var node = cat;
    final parent = byId[cat.parentId];
    if (!children.containsKey(cat.id) &&
        parent != null &&
        _sameName(parent, cat)) {
      node = parent;
    }

    if (children.containsKey(node.id)) {
      final leaves = [
        for (final k in children[node.id]!)
          if (!children.containsKey(k.id)) k,
      ];
      final samePrice = [
        for (final l in leaves)
          if (_samePrice(l.price, newPrice)) l,
      ];
      for (final l in samePrice) {
        if (compatible(l)) {
          return PricePlan(
            kind: PlanKind.reuseLeaf,
            reason: PlanReason.samePrice,
            request: request,
            leafId: l.id,
          );
        }
      }
      // The template for the new leaf: the one asked about, else the newest.
      final template = !children.containsKey(cat.id)
          ? cat
          : (leaves.isEmpty
                ? node
                : ([...leaves]..sort(
                    (a, b) => a.createdAt.compareTo(b.createdAt),
                  )).last);
      return PricePlan(
        kind: PlanKind.addLeaf,
        reason: samePrice.isNotEmpty
            ? PlanReason.accountsIncompatible
            : PlanReason.priceChanged,
        request: request,
        aggregateId: node.id,
        newLeaf: _leafInput(
          template,
          name: template.name,
          price: newPrice,
          parentId: node.id,
          accountCountId: accountCountId,
          accountUseId: accountUseId,
        ),
      );
    }

    // A simple leaf.
    final samePrice = _samePrice(cat.price, newPrice);
    if (samePrice && compatible(cat)) {
      return PricePlan(
        kind: PlanKind.reuseLeaf,
        reason: PlanReason.samePrice,
        request: request,
        leafId: cat.id,
      );
    }
    return PricePlan(
      kind: PlanKind.wrapper,
      reason: samePrice
          ? PlanReason.accountsIncompatible
          : PlanReason.priceChanged,
      request: request,
      oldLeafId: cat.id,
      wrapper: CategoryInput(
        name: cat.name,
        isIncome: cat.isIncome,
        oneTime: cat.oneTime,
        unit: BudgetUnit.fromDb(cat.unit),
        price: null,
        parentId: cat.parentId,
        accountCountId: cat.accountCountId,
        accountUseId: cat.accountUseId,
      ),
      newLeaf: _leafInput(
        cat,
        name: cat.name,
        price: newPrice,
        parentId: null, // the wrapper, at apply time
        accountCountId: accountCountId,
        accountUseId: accountUseId,
      ),
    );
  }

  /// C7: a one-off household/hygiene item bought for [cost] that belongs under
  /// [groupId]. An existing leaf of that name is handled like any product
  /// ([plan]); otherwise a new `piece` leaf with price = cost. Never targets
  /// the group itself.
  Future<PricePlan> planOneOff({
    required String name,
    required String groupId,
    required double cost,
    String? accountCountId,
    String? accountUseId,
    String? preferredIcon,
  }) async {
    if (!(cost > 0) || cost.isInfinite) {
      throw ArgumentError.value(cost, 'cost', 'must be positive');
    }
    final group = await (db.select(
      db.budgetCategoriesTable,
    )..where((t) => t.id.equals(groupId))).getSingleOrNull();
    if (group == null) {
      throw const MissingRowException('That category no longer exists.');
    }
    final key = normalizeReceiptText(name);
    final siblings = await (db.select(
      db.budgetCategoriesTable,
    )..where((t) => t.parentId.equals(groupId))).get();
    for (final s in siblings) {
      if (normalizeReceiptText(s.name) == key) {
        return plan(
          categoryId: s.id,
          newPrice: cost,
          accountCountId: accountCountId,
          accountUseId: accountUseId,
        );
      }
    }
    return PricePlan(
      kind: PlanKind.oneOffLeaf,
      reason: PlanReason.oneOff,
      request: PlanRequest(
        categoryId: groupId,
        newPrice: cost,
        accountCountId: accountCountId,
        accountUseId: accountUseId,
        oneOffName: name,
      ),
      newLeaf: CategoryInput(
        name: withSafeIcon(name, preferred: preferredIcon),
        unit: BudgetUnit.piece,
        price: cost,
        parentId: groupId,
        accountCountId: accountCountId ?? group.accountCountId,
        accountUseId: accountUseId ?? group.accountUseId,
      ),
    );
  }

  /// Executes [plan] in ONE transaction and returns the leaf to attach the
  /// transaction to.
  ///
  /// Idempotency: `saveCategory` cannot take a caller-chosen id for a new row,
  /// so there are no deterministic ids. Instead the request is re-planned
  /// inside the transaction against the CURRENT data: running the same plan
  /// twice (a retried job) finds the leaf the first run created and returns it
  /// with nothing created. The plan passed in is therefore advisory; what runs
  /// is the fresh plan for the same request.
  Future<AppliedPlan> apply(PricePlan plan) {
    return db.transaction(() async {
      final r = plan.request;
      final fresh = r.oneOffName != null
          ? await planOneOff(
              name: r.oneOffName!,
              groupId: r.categoryId,
              cost: r.newPrice,
              accountCountId: r.accountCountId,
              accountUseId: r.accountUseId,
              // The icon was already chosen into the plan's name.
              preferredIcon: plan.newLeaf == null
                  ? null
                  : leadingIconOf(plan.newLeaf!.name),
            )
          : await this.plan(
              categoryId: r.categoryId,
              newPrice: r.newPrice,
              accountCountId: r.accountCountId,
              accountUseId: r.accountUseId,
            );
      switch (fresh.kind) {
        case PlanKind.reuseLeaf:
          return AppliedPlan(leafId: fresh.leafId!);
        case PlanKind.addLeaf:
        case PlanKind.oneOffLeaf:
          final id = await budget.saveCategory(fresh.newLeaf!);
          return AppliedPlan(leafId: id, createdIds: [id]);
        case PlanKind.wrapper:
          final wrapperId = await budget.saveCategory(fresh.wrapper!);
          await budget.moveCategory(fresh.oldLeafId!, wrapperId);
          final leafInput = fresh.newLeaf!;
          final leafId = await budget.saveCategory(
            CategoryInput(
              name: leafInput.name,
              isIncome: leafInput.isIncome,
              oneTime: leafInput.oneTime,
              unit: leafInput.unit,
              price: leafInput.price,
              parentId: wrapperId,
              accountCountId: leafInput.accountCountId,
              accountUseId: leafInput.accountUseId,
            ),
          );
          return AppliedPlan(
            leafId: leafId,
            createdIds: [wrapperId, leafId],
            movedIds: [fresh.oldLeafId!],
          );
      }
    });
  }

  // ---- C8 snacks, C9 budget quantities ---------------------------------------

  /// The «Снеки (асорті)» leaf (unit piece, price 1), or null. Matched by name
  /// (icon, case ignored) starting with "снеки".
  Future<String?> findSnacksCategory() async {
    final rows =
        await (db.select(db.budgetCategoriesTable)
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
            .get();
    final parents = {for (final c in rows) c.parentId};
    for (final c in rows) {
      if (parents.contains(c.id)) continue; // a group
      if (c.unit != BudgetUnit.piece.db) continue;
      if (normalizeReceiptText(c.name).startsWith('снеки')) return c.id;
    }
    return null;
  }

  static bool _sameName(BudgetCategory a, BudgetCategory b) =>
      normalizeReceiptText(a.name) == normalizeReceiptText(b.name);

  static CategoryInput _leafInput(
    BudgetCategory template, {
    required String name,
    required double price,
    required String? parentId,
    required String? accountCountId,
    required String? accountUseId,
  }) => CategoryInput(
    name: name,
    isIncome: template.isIncome,
    oneTime: template.oneTime,
    unit: BudgetUnit.fromDb(template.unit),
    price: price,
    parentId: parentId,
    accountCountId: accountCountId ?? template.accountCountId,
    accountUseId: accountUseId ?? template.accountUseId,
  );
}

/// C4 / I4: a leaf fits how the purchase was paid when, for each wanted
/// account, the leaf has the same one. A null WANTED account is "no
/// constraint"; a null account on the LEAF is "unspecified" and also fits.
bool accountsCompatible({
  required String? leafCount,
  required String? leafUse,
  required String? wantCount,
  required String? wantUse,
}) {
  bool ok(String? leaf, String? want) =>
      want == null || leaf == null || leaf == want;
  return ok(leafCount, wantCount) && ok(leafUse, wantUse);
}

/// C9: the quantity to record for an amount spent on [category]. Budget-type
/// categories (price = monthly budget) take amount / price; direct-amount ones
/// (price 1) take the amount; percent categories store the amount itself.
double quantityForSpend({
  required double amount,
  required double? price,
  BudgetUnit unit = BudgetUnit.month,
}) {
  if (unit == BudgetUnit.percentPerMonth) return amount;
  if (price == null || !(price > 0)) return amount;
  return (amount / price * 1e6).round() / 1e6;
}

// ---- C11 icons ------------------------------------------------------------------

/// Long-established emoji (Unicode <= 9, single code point, no variation
/// selector) that every platform and the Notion API accept.
const kSafeCategoryIcons = <String>{
  '🛒', '🍎', '🍏', '🍌', '🍇', '🍓', '🍋', '🍅', '🥕', '🥔', '🌽', '🥦',
  '🥬', '🍞', '🥖', '🧀', '🥚', '🥛', '🍗', '🥩', '🐟', '🍝', '🍚', '🍯',
  '🍫', '🍬', '🍪', '🍿', '☕', '🍵', '🍺', '🍷', '🧃', '💧', '🧴', '🧼',
  '🧽', '🧻', '🪥', '💊', '👕', '👟', '🎁', '🏠', '🚗', '⚽', '📚', '🔧',
  '💡', '🐶', '🐱', '👶', '💰', '🍽', '🍕', '🍔', '🌿', '🍄', '🥜', '🥫',
};

const _fallbackIcon = '🛒';

const _iconKeywords = <String, String>{
  'яблук': '🍎', 'банан': '🍌', 'морк': '🥕', 'карто': '🥔', 'хліб': '🍞',
  'сир': '🧀', 'яйц': '🥚', 'молок': '🥛', "м'яс": '🥩', 'риб': '🐟',
  'макарон': '🍝', 'кав': '☕', 'чай': '🍵', 'мило': '🧼', 'дезодорант': '🧴',
  'зубн': '🪥', 'папір': '🧻', 'ліки': '💊', 'зелен': '🌿', 'гриб': '🍄',
};

final _leadingIconRe = RegExp(r'^([^\p{L}\p{N}\s]+)\s+', unicode: true);

/// The emoji a [name] starts with ("🍎 Яблука" -> "🍎"), else null.
String? leadingIconOf(String name) {
  final m = _leadingIconRe.firstMatch(name);
  if (m == null) return null;
  final icon = m.group(1)!;
  return icon.runes.any((r) => r >= 0x2190) ? icon : null;
}

bool isSafeIcon(String icon) => kSafeCategoryIcons.contains(icon);

/// [name] with a safe leading icon: keeps its own when safe, else uses
/// [preferred] when safe, else a keyword guess, else a shopping cart.
String withSafeIcon(String name, {String? preferred}) {
  final own = leadingIconOf(name);
  if (own != null && isSafeIcon(own)) return name;
  final bare = own == null ? name.trim() : name.substring(own.length).trim();
  var icon = preferred != null && isSafeIcon(preferred) ? preferred : null;
  if (icon == null) {
    final folded = normalizeReceiptText(bare);
    for (final e in _iconKeywords.entries) {
      if (folded.contains(e.key)) {
        icon = e.value;
        break;
      }
    }
  }
  return '${icon ?? _fallbackIcon} $bare';
}
