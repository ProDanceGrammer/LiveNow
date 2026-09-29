import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/sequence_naming.dart';

void main() {
  test('parseSequencePrefix splits number and base name', () {
    expect(parseSequencePrefix('[#2] Read a Bible'), (2, 'Read a Bible'));
    expect(parseSequencePrefix('[#12]Read'), (12, 'Read'));
    expect(parseSequencePrefix('Read a Bible'), (null, 'Read a Bible'));
    expect(parseSequencePrefix('Read [#2] later'), (null, 'Read [#2] later'));
  });

  test('formatSequenceName adds the prefix', () {
    expect(formatSequenceName(3, 'Read a Bible'), '[#3] Read a Bible');
  });

  test('normalizeForMatch ignores prefix, digits, case and padding', () {
    expect(normalizeForMatch('[#2] Read a Bible'), 'read a bible');
    expect(normalizeForMatch('Read a Bible 5'), 'read a bible');
    expect(normalizeForMatch('  READ A BIBLE  '), 'read a bible');
    expect(normalizeForMatch('Pray'), isNot(normalizeForMatch('Read')));
  });
}
