import '../../data/database.dart';
import '../budget_rules.dart';
import 'alias_source.dart';

/// One price variant of a product: a leaf with its own price and accounts.
class CategoryVariant {
  const CategoryVariant({
    required this.id,
    required this.name,
    required this.price,
    required this.accountCountId,
    required this.accountUseId,
  });

  final String id;
  final String name;
  final double? price;
  final String? accountCountId;
  final String? accountUseId;
}

/// A category that may be what a receipt line means.
class CategoryCandidate {
  const CategoryCandidate({
    required this.id,
    required this.name,
    required this.parentId,
    required this.parentName,
    required this.isAggregate,
    required this.unit,
    required this.price,
    required this.accountCountId,
    required this.accountUseId,
    required this.score,
    required this.fromAlias,
    required this.variants,
  });

  final String id;

  /// Includes the emoji icon.
  final String name;
  final String? parentId;
  final String? parentName;

  /// Has sub-categories (carries no price and no transactions).
  final bool isAggregate;
  final BudgetUnit unit;
  final double? price;
  final String? accountCountId;
  final String? accountUseId;

  /// 0..1; 1 = the name is the product (or a learned alias).
  final double score;
  final bool fromAlias;

  /// For an aggregate: its direct leaves. For a leaf: the OTHER leaves with the
  /// same name under the same parent (older/newer prices of the same product).
  final List<CategoryVariant> variants;
}

class ResolveResult {
  const ResolveResult({
    required this.candidates,
    required this.ambiguous,
    this.alias,
  });

  /// Best first.
  final List<CategoryCandidate> candidates;

  /// The top candidates are too close (or too weak): ask the user / the model.
  final bool ambiguous;

  /// The alias that decided candidate 0, when there was one (unit/weight
  /// defaults travel with it).
  final AliasEntry? alias;

  CategoryCandidate? get best => candidates.isEmpty ? null : candidates.first;
  double get confidence => best?.score ?? 0;
  bool get isEmpty => candidates.isEmpty;
}

/// Rules C2, C3, C13: ranks the categories a product name may belong to. Alias
/// memory first, then a fuzzy match over leaves AND aggregates. Read-only: it
/// never creates anything. Different brands/varieties are separate candidates;
/// the leaves of one product's price history are folded into their wrapper.
class CategoryResolver {
  CategoryResolver(this.db, {this.aliases});

  final AppDatabase db;
  final AliasSource? aliases;

  /// Candidates scoring below this are dropped.
  static const double minScore = 0.4;

  /// Top candidates closer than this are "ambiguous".
  static const double ambiguityGap = 0.1;

  Future<ResolveResult> resolve(String productName, {int limit = 5}) async {
    final all = await db.select(db.budgetCategoriesTable).get();
    final byId = {for (final c in all) c.id: c};
    final children = <String, List<BudgetCategory>>{};
    for (final c in all) {
      final p = c.parentId;
      if (p != null && byId.containsKey(p)) (children[p] ??= []).add(c);
    }

    CategoryCandidate build(BudgetCategory c, double score, bool fromAlias) {
      final kids = children[c.id];
      final key = nameKey(c.name);
      final List<BudgetCategory> variants;
      if (kids != null) {
        variants = [
          for (final k in kids)
            if (!children.containsKey(k.id)) k,
        ];
      } else {
        variants = [
          for (final s in children[c.parentId] ?? const <BudgetCategory>[])
            if (s.id != c.id &&
                !children.containsKey(s.id) &&
                nameKey(s.name) == key)
              s,
        ];
      }
      return CategoryCandidate(
        id: c.id,
        name: c.name,
        parentId: c.parentId,
        parentName: byId[c.parentId]?.name,
        isAggregate: kids != null,
        unit: BudgetUnit.fromDb(c.unit),
        price: c.price,
        accountCountId: c.accountCountId,
        accountUseId: c.accountUseId,
        score: score,
        fromAlias: fromAlias,
        variants: [
          for (final v in variants)
            CategoryVariant(
              id: v.id,
              name: v.name,
              price: v.price,
              accountCountId: v.accountCountId,
              accountUseId: v.accountUseId,
            ),
        ],
      );
    }

    // 1. Alias memory.
    AliasEntry? alias;
    final aliasSource = aliases;
    if (aliasSource != null) {
      alias = await aliasSource.lookup(normalizeReceiptText(productName));
      if (alias != null && !byId.containsKey(alias.categoryId)) alias = null;
    }

    // 2. Fuzzy match.
    final query = _tokens(productName);
    final scored = <({BudgetCategory c, double score})>[];
    // Names that contain every query word and more: the query alone does not
    // say which of them is meant.
    final underSpecified = <String>{};
    for (final c in all) {
      if (alias != null && c.id == alias.categoryId) continue;
      final s = matchScore(query, _tokens(c.name));
      if (s >= minScore) scored.add((c: c, score: s));
      if (s >= minScore && _coversQuery(query, _tokens(c.name))) {
        underSpecified.add(c.id);
      }
    }
    // A leaf of a same-name wrapper is represented by the wrapper.
    final matchedIds = {for (final s in scored) s.c.id};
    scored.removeWhere((s) {
      final p = s.c.parentId;
      return p != null &&
          matchedIds.contains(p) &&
          children.containsKey(p) &&
          !children.containsKey(s.c.id) &&
          nameKey(byId[p]!.name) == nameKey(s.c.name);
    });
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      // Prefer the more specific node (a leaf) on a tie, then a stable order.
      final byLeaf = (children.containsKey(a.c.id) ? 1 : 0).compareTo(
        children.containsKey(b.c.id) ? 1 : 0,
      );
      return byLeaf != 0 ? byLeaf : a.c.name.compareTo(b.c.name);
    });

    final candidates = <CategoryCandidate>[
      if (alias != null) build(byId[alias.categoryId]!, 1.0, true),
      for (final s in scored) build(s.c, s.score, false),
    ].take(limit).toList();

    return ResolveResult(
      candidates: candidates,
      ambiguous: _isAmbiguous(candidates, underSpecified),
      alias: alias,
    );
  }

  static bool _isAmbiguous(List<CategoryCandidate> c, Set<String> under) {
    if (c.isEmpty) return false;
    final top = c.first;
    if (top.fromAlias) return false;
    if (top.score < 0.5) return true;
    final topKey = nameKey(top.name);
    if (top.score < 1 && under.contains(top.id)) {
      for (final other in c.skip(1)) {
        if (nameKey(other.name) != topKey && under.contains(other.id)) {
          return true;
        }
      }
    }
    // Same-name candidates are price variants of ONE product, not a choice.
    final key = nameKey(top.name);
    for (final other in c.skip(1)) {
      if (nameKey(other.name) == key) continue;
      return top.score - other.score < ambiguityGap;
    }
    return false;
  }

  /// Name without its icon, folded like every search in the app.
  static String nameKey(String name) => normalizeReceiptText(name);

  static final _split = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
  static final _number = RegExp(r'^\p{N}+$', unicode: true);

  static List<String> _tokens(String text) => [
    for (final t in nameKey(text).split(_split))
      if (t.length >= 2 && !_number.hasMatch(t)) t,
  ];

  /// Every query word is found in the name's words.
  static bool _coversQuery(List<String> query, List<String> name) =>
      query.isNotEmpty &&
      query.every((q) => name.any((n) => _tokenMatch(q, n)));

  static bool _tokenMatch(String a, String b) {
    if (a == b) return true;
    final shorter = a.length < b.length ? a.length : b.length;
    var common = 0;
    while (common < shorter && a.codeUnitAt(common) == b.codeUnitAt(common)) {
      common++;
    }
    // A shared stem: "яблука" ~ "яблуко", "sebze" ~ "sebzeler".
    return common >= 4 && common >= shorter * 0.7;
  }

  /// 0..1 similarity of the product tokens [query] and a category's [name]
  /// tokens (Dice coefficient over stem-matched tokens; all name tokens present
  /// in the query counts at least 0.7).
  static double matchScore(List<String> query, List<String> name) {
    if (query.isEmpty || name.isEmpty) return 0;
    final free = [...query];
    var matched = 0;
    for (final n in name) {
      final at = free.indexWhere((q) => _tokenMatch(q, n));
      if (at >= 0) {
        matched++;
        free.removeAt(at);
      }
    }
    if (matched == 0) return 0;
    final dice = 2 * matched / (query.length + name.length);
    if (matched == name.length && query.length == name.length) return 1.0;
    return matched == name.length && dice < 0.7 ? 0.7 : dice;
  }
}
