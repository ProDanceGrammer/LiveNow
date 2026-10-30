import '../budget_icons.dart';
import '../search_match.dart';

/// What the assistant has learned about a receipt text: which category it
/// belongs to and per-product defaults (rule Q4, "corrections are rules").
class AliasEntry {
  const AliasEntry({
    required this.categoryId,
    this.unitOverride,
    this.weightGramsDefault,
    this.pieceDefault,
    this.source = 'user',
  });

  final String categoryId;

  /// `piece` / `kilogram` when the user overruled the unit rule (U2).
  final String? unitOverride;

  /// Typical weight of one piece (U7: "a loaf is about 200 g").
  final double? weightGramsDefault;

  /// Count per pack when it is not printed.
  final int? pieceDefault;

  /// `user` or `ai`.
  final String source;
}

/// Alias memory. The database-backed implementation (`product_aliases`) comes
/// with the schema phase; the resolver only depends on this interface.
abstract class AliasSource {
  /// The alias for [normalizedReceiptText] (see [normalizeReceiptText]), or
  /// null when nothing was learned for it.
  Future<AliasEntry?> lookup(String normalizedReceiptText);
}

/// The one normalisation used as an alias key: no leading emoji, case, Turkish
/// dotted/dotless i, apostrophes and runs of spaces folded.
String normalizeReceiptText(String text) => foldSearch(stripLeadingIcon(text));

/// Map-backed [AliasSource] for tests and as a cache.
class InMemoryAliasSource implements AliasSource {
  InMemoryAliasSource([Map<String, AliasEntry> aliases = const {}]) {
    aliases.forEach(add);
  }

  final Map<String, AliasEntry> _byKey = {};

  /// Remembers [alias] for [receiptText] (normalised here).
  void add(String receiptText, AliasEntry alias) {
    _byKey[normalizeReceiptText(receiptText)] = alias;
  }

  @override
  Future<AliasEntry?> lookup(String normalizedReceiptText) async =>
      _byKey[normalizedReceiptText];
}
