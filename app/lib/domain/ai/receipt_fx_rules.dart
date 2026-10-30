// Receipt FX rules (spec A3-A5): pure. rate_count = units of the COUNT account
// currency per 1 base (EUR); rate_interact = units of the USE account currency
// per 1 base. A bank screenshot "1 count unit = r use units" (e.g. UAH per TRY)
// has priority. A same-currency pair gets the REAL market rate on both sides,
// never a placeholder 1 (except the base currency itself).

enum FxSource { screenshot, market, unresolved }

enum FxWarning {
  /// A needed market rate is missing: ask the user or fetch one.
  noMarketRate,

  /// A rate is further than the tolerance from the last known one (A4).
  farFromLastKnown,

  /// A screenshot rate was given for two equal currencies and was ignored.
  screenshotIgnoredSameCurrency,
}

class ReceiptFx {
  const ReceiptFx(
    this.rateCount,
    this.rateInteract,
    this.source, [
    this.warnings = const [],
  ]);
  final double? rateCount;
  final double? rateInteract;
  final FxSource source;
  final List<FxWarning> warnings;

  bool get resolved => rateCount != null && rateInteract != null;
}

/// The rate shown by a bank screenshot: use-currency units per 1 count unit
/// (961.69 UAH / 1051.95 TRY = 0.9142), rounded to the 4 digits the bank shows.
double? screenshotRateFromAmounts({
  required double useAmount,
  required double countAmount,
}) {
  if (countAmount <= 0 || useAmount <= 0) return null;
  return (useAmount / countAmount * 10000).round() / 10000;
}

/// [marketEurRates]: currency code -> units per 1 base currency (optional
/// suggestions the user confirmed). [lastKnownRateCount]/[lastKnownRateInteract]
/// are only for the sanity check, which returns a warning, never throws.
ReceiptFx computeReceiptRates({
  required String countCurrency,
  required String useCurrency,
  double? screenshotRate,
  Map<String, double> marketEurRates = const {},
  double? lastKnownRateCount,
  double? lastKnownRateInteract,
  String baseCurrency = 'EUR',
  double tolerance = 3.0,
}) {
  final count = countCurrency.toUpperCase();
  final use = useCurrency.toUpperCase();
  final base = baseCurrency.toUpperCase();
  double? market(String c) {
    if (c == base) return 1.0;
    final v = marketEurRates[c];
    return (v != null && v > 0) ? v : null;
  }

  final warnings = <FxWarning>[];
  double? rc;
  double? ri;
  var source = FxSource.market;
  final sameCurrency = count == use;
  final screenshot = (screenshotRate != null && screenshotRate > 0)
      ? screenshotRate
      : null;

  if (screenshot != null && sameCurrency) {
    warnings.add(FxWarning.screenshotIgnoredSameCurrency);
  }
  if (screenshot != null && !sameCurrency) {
    source = FxSource.screenshot;
    final mc = market(count);
    final mi = market(use);
    if (mc != null) {
      rc = mc;
      ri = mc * screenshot;
    } else if (mi != null) {
      ri = mi;
      rc = mi / screenshot;
    }
  } else {
    rc = market(count);
    ri = sameCurrency ? rc : market(use);
  }
  if (rc == null || ri == null) {
    return ReceiptFx(null, null, FxSource.unresolved, [
      ...warnings,
      FxWarning.noMarketRate,
    ]);
  }
  if ((lastKnownRateCount != null &&
          (rc - lastKnownRateCount).abs() > tolerance) ||
      (lastKnownRateInteract != null &&
          (ri - lastKnownRateInteract).abs() > tolerance)) {
    warnings.add(FxWarning.farFromLastKnown);
  }
  return ReceiptFx(rc, ri, source, warnings);
}

/// A late screenshot arrived (A4.3): the new rates for an already recorded
/// receipt, from the amounts the bank shows.
ReceiptFx recomputeWithScreenshot({
  required String countCurrency,
  required String useCurrency,
  required double countAmount,
  required double useAmount,
  Map<String, double> marketEurRates = const {},
  String baseCurrency = 'EUR',
}) => computeReceiptRates(
  countCurrency: countCurrency,
  useCurrency: useCurrency,
  screenshotRate: screenshotRateFromAmounts(
    useAmount: useAmount,
    countAmount: countAmount,
  ),
  marketEurRates: marketEurRates,
  baseCurrency: baseCurrency,
);

/// I5: does interact/count agree with the screenshot rate (relative [tol])?
bool ratioMatchesScreenshot(
  double rateCount,
  double rateInteract,
  double screenshotRate, {
  double tol = 0.01,
}) =>
    rateCount > 0 &&
    ((rateInteract / rateCount) - screenshotRate).abs() <=
        screenshotRate * tol;
