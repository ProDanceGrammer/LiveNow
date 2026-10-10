import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/widgets/budget_format.dart';

void main() {
  setUpAll(initPostponeTimeZoneData);

  test('budgetNumber trims zeros but keeps tiny rates non-zero', () {
    expect(budgetNumber(100), '100');
    expect(budgetNumber(0.5), '0.5');
    expect(budgetNumber(55.9), '55.9');
    expect(budgetNumber(0), '0');
    expect(budgetNumber(0.00001782881), '0.0000178288');
    expect(
      parseBudgetNumber(budgetNumber(0.00001782881)),
      closeTo(1.78288e-5, 1e-10),
    );
  });

  test('budgetMoney: two decimals, real minus, optional plus', () {
    expect(budgetMoney(-12.5), '−12.50');
    expect(budgetMoney(3, sign: true), '+3.00');
    expect(budgetMoney(-0.001), '0.00');
  });

  test('parseBudgetNumber accepts comma and rejects garbage', () {
    expect(parseBudgetNumber('1,5'), 1.5);
    expect(parseBudgetNumber(' 2 '), 2);
    expect(parseBudgetNumber(''), isNull);
    expect(parseBudgetNumber('x'), isNull);
  });

  test('budgetNoonUtc keeps the calendar day in the app time zone', () {
    final noon = budgetNoonUtc(DateTime(2026, 10, 10));
    expect(budgetDate(noon, now: noon), '10 Oct');
    expect(budgetLocalDay(noon), DateTime(2026, 10, 10));
  });
}
