/// "Does this product already exist?": the check that comes BEFORE the assistant
/// suggests a new category. A category counts as the product when its name is
/// similar (it came out of [CategoryResolver]), its price is the paid price, and
/// its accounts fit the receipt's. Pure; no database.
library;

import 'category_resolver.dart';
import 'price_planner.dart' show accountsCompatible, pricesMatch;

/// The id of an existing leaf that already is this product at [unitPrice] with
/// accounts compatible with [useAccountId] (the account the receipt was paid
/// from), or null. [similar] are resolver candidates that are products (the
/// caller drops groups); a same-name wrapper is looked into through its
/// `variants`. A line whose price is not known yet matches nothing: it is asked,
/// with the similar categories offered first.
String? findExistingMatch(
  Iterable<CategoryCandidate> similar, {
  required double? unitPrice,
  required String? useAccountId,
}) {
  if (unitPrice == null || !(unitPrice > 0) || unitPrice.isInfinite) return null;
  bool fits(double? price, String? count, String? use) =>
      pricesMatch(price, unitPrice) &&
      accountsCompatible(leafCount: count, leafUse: use, wantCount: null, wantUse: useAccountId);
  for (final c in similar) {
    if (!c.isAggregate && fits(c.price, c.accountCountId, c.accountUseId)) return c.id;
    for (final v in c.variants) {
      if (fits(v.price, v.accountCountId, v.accountUseId)) return v.id;
    }
  }
  return null;
}
