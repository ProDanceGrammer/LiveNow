import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/ai/extracted_receipt.dart';
import 'package:livenow/domain/ai/sum_verifier.dart';

void main() {
  test('I2 sum within 0.02 is ok', () {
    expect(verifySum([10.01, 20.00], 30.00).ok, isTrue);
    expect(verifySum([10.02, 20.00], 30.00).ok, isTrue);
    expect(verifySum(const [0.1, 0.2], 0.3).ok, isTrue);
  });

  test('I2 a mismatch is reported with the difference, not fixed', () {
    final c = verifySum([10.00, 20.00], 30.50);
    expect(c.ok, isFalse);
    expect(c.difference, -0.50);
    expect(c.linesSum, 30.00);
    expect(c.expected, 30.50);
    expect(verifySum([10.00, 20.05], 30.00).difference, 0.05);
  });

  test('I2 a user tender amount can be the expected sum', () {
    expect(verifySum([99.95, 95.50], 195.45).ok, isTrue);
  });

  const mine = Tender(method: 'card', last4: '6141', amount: 195.45);
  const other = Tender(method: 'card', last4: '9999', amount: 149.00);
  final lines = [99.95, 95.50, 25.00, 25.00, 99.00];

  test('E2 A6 split tender: 99+25+25 is the other card, rest is mine', () {
    final s = splitTenders(
      lineNets: lines,
      tenders: const [other, mine],
      myLast4: {'6141'},
    );
    expect(s.status, SplitStatus.split);
    expect(s.mine, [0, 1]);
    expect(s.others, [2, 3, 4]);
    expect(s.needsQuestion, isFalse);
    expect(verifySum(lines, 344.45).ok, isTrue);
    expect(verifySum(s.mine.map((i) => lines[i]), 195.45).ok, isTrue);
  });

  test('A6 my tender can be found by amount (bank screenshot)', () {
    final s = splitTenders(
      lineNets: lines,
      tenders: const [other, mine],
      amountHint: 195.45,
    );
    expect(s.status, SplitStatus.split);
    expect(s.mine, [0, 1]);
  });

  test('A6 a single tender means every line is mine', () {
    final s = splitTenders(
      lineNets: lines,
      tenders: const [Tender(method: 'card', amount: 344.45)],
    );
    expect(s.status, SplitStatus.allMine);
    expect(s.mine, [0, 1, 2, 3, 4]);
  });

  test('A6 an ambiguous subset is flagged for a question', () {
    final s = splitTenders(
      lineNets: [10, 10, 20],
      tenders: const [
        Tender(method: 'card', last4: '1111', amount: 20),
        Tender(method: 'card', last4: '2222', amount: 20),
      ],
      myLast4: {'1111'},
    );
    expect(s.status, SplitStatus.ambiguous);
    expect(s.needsQuestion, isTrue);
  });

  test('A6 no subset adds up: flagged, nothing is guessed', () {
    final s = splitTenders(
      lineNets: [10, 20],
      tenders: const [
        Tender(method: 'card', last4: '1111', amount: 25),
        Tender(method: 'card', last4: '2222', amount: 5),
      ],
      myLast4: {'1111'},
    );
    expect(s.status, SplitStatus.noMatch);
    expect(s.mine, isEmpty);
    expect(s.needsQuestion, isTrue);
  });

  test('A6 two tenders and no way to tell which is mine: ask', () {
    final s = splitTenders(lineNets: lines, tenders: const [other, mine]);
    expect(s.status, SplitStatus.unknownTender);
    expect(s.needsQuestion, isTrue);
  });
}
