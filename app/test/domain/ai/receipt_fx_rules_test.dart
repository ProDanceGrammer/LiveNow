import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/ai/receipt_fx_rules.dart';

void main() {
  const market = {'TRY': 48.0, 'UAH': 44.0};

  test('A3 count TRY, use UAH from the market: one rate per side', () {
    final fx = computeReceiptRates(
      countCurrency: 'TRY',
      useCurrency: 'UAH',
      marketEurRates: market,
    );
    expect(fx.source, FxSource.market);
    expect(fx.rateCount, 48.0);
    expect(fx.rateInteract, 44.0);
  });

  test('A4 a screenshot rate has priority: interact = count x r', () {
    final fx = computeReceiptRates(
      countCurrency: 'TRY',
      useCurrency: 'UAH',
      screenshotRate: 0.9142,
      marketEurRates: market,
    );
    expect(fx.source, FxSource.screenshot);
    expect(fx.rateCount, 48.0);
    expect(fx.rateInteract, closeTo(48.0 * 0.9142, 1e-9));
  });

  test('A4 screenshot with only the use-currency market rate', () {
    final fx = computeReceiptRates(
      countCurrency: 'TRY',
      useCurrency: 'UAH',
      screenshotRate: 0.9142,
      marketEurRates: const {'UAH': 44.0},
    );
    expect(fx.rateInteract, 44.0);
    expect(fx.rateCount, closeTo(44.0 / 0.9142, 1e-9));
  });

  test('A5 same currency: both sides are the real rate, never 1', () {
    final fx = computeReceiptRates(
      countCurrency: 'TRY',
      useCurrency: 'TRY',
      marketEurRates: market,
    );
    expect(fx.rateCount, 48.0);
    expect(fx.rateInteract, 48.0);
    final uah = computeReceiptRates(
      countCurrency: 'UAH',
      useCurrency: 'UAH',
      marketEurRates: market,
    );
    expect(uah.rateCount, 44.0);
    expect(uah.rateInteract, 44.0);
  });

  test('A5 same currency without a market rate stays unresolved (no 1)', () {
    final fx = computeReceiptRates(
      countCurrency: 'TRY',
      useCurrency: 'TRY',
      marketEurRates: const {},
    );
    expect(fx.resolved, isFalse);
    expect(fx.rateCount, isNull);
    expect(fx.warnings, contains(FxWarning.noMarketRate));
  });

  test('A5 a screenshot for equal currencies is ignored with a warning', () {
    final fx = computeReceiptRates(
      countCurrency: 'TRY',
      useCurrency: 'TRY',
      screenshotRate: 1.0,
      marketEurRates: market,
    );
    expect(fx.rateInteract, 48.0);
    expect(fx.warnings, contains(FxWarning.screenshotIgnoredSameCurrency));
  });

  test('A3 the base currency itself is exactly 1', () {
    final fx = computeReceiptRates(
      countCurrency: 'EUR',
      useCurrency: 'EUR',
    );
    expect(fx.rateCount, 1.0);
    expect(fx.rateInteract, 1.0);
  });

  test('A4 sanity check: far from the last known rate is a warning only', () {
    final far = computeReceiptRates(
      countCurrency: 'TRY',
      useCurrency: 'UAH',
      marketEurRates: market,
      lastKnownRateInteract: 40.0,
    );
    expect(far.resolved, isTrue);
    expect(far.warnings, contains(FxWarning.farFromLastKnown));
    final near = computeReceiptRates(
      countCurrency: 'TRY',
      useCurrency: 'UAH',
      marketEurRates: market,
      lastKnownRateInteract: 42.0,
      lastKnownRateCount: 47.0,
    );
    expect(near.warnings, isEmpty);
  });

  test('A4 a late screenshot: 961.69 UAH / 1051.95 TRY = 0.9142', () {
    expect(
      screenshotRateFromAmounts(useAmount: 961.69, countAmount: 1051.95),
      0.9142,
    );
    final fx = recomputeWithScreenshot(
      countCurrency: 'TRY',
      useCurrency: 'UAH',
      countAmount: 1051.95,
      useAmount: 961.69,
      marketEurRates: market,
    );
    expect(fx.source, FxSource.screenshot);
    expect(fx.rateInteract, closeTo(48.0 * 0.9142, 1e-9));
    expect(
      ratioMatchesScreenshot(fx.rateCount!, fx.rateInteract!, 0.9142),
      isTrue,
    );
    expect(ratioMatchesScreenshot(48, 30, 0.9142), isFalse);
  });

  test('A4 a zero amount gives no screenshot rate', () {
    expect(screenshotRateFromAmounts(useAmount: 10, countAmount: 0), isNull);
  });
}
