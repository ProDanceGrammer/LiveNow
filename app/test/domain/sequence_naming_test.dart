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

  group('edge cases', () {
    test('a huge number is not a prefix and never throws', () {
      const huge = '[#99999999999999999999] Pray';
      expect(parseSequencePrefix(huge), (null, huge));
      // The longest number that still counts as a prefix.
      expect(parseSequencePrefix('[#999999999] Pray'), (999999999, 'Pray'));
      expect(parseSequencePrefix('[#1000000000] Pray'), (null, '[#1000000000] Pray'));
    });

    test('a title that is only a prefix has an empty base name', () {
      expect(parseSequencePrefix('[#3]'), (3, ''));
      expect(parseSequencePrefix('[#3]   '), (3, ''));
      expect(formatSequenceName(4, ''), '[#4]'); // no trailing space
      expect(normalizeForMatch('[#3]'), '');
    });

    test('leading zeros are read as the number and not kept', () {
      expect(parseSequencePrefix('[#0] Pray'), (0, 'Pray'));
      expect(parseSequencePrefix('[#007] Pray'), (7, 'Pray'));
      expect(formatSequenceName(8, 'Pray'), '[#8] Pray');
    });

    test('malformed prefixes are plain text', () {
      for (final name in ['[#] Pray', '[# 2] Pray', '[#-1] Pray', '[#2 Pray', '#2] Pray', ' [#2] Pray']) {
        expect(parseSequencePrefix(name), (null, name), reason: name);
      }
    });

    test('(pinned) names made only of digits all match each other', () {
      // Every digit run is stripped, so these three have the same key.
      expect(normalizeForMatch('123'), '');
      expect(normalizeForMatch('[#2] 2024'), '');
      expect(normalizeForMatch('42'), normalizeForMatch('2024'));
    });
  });

  test('normalizeForMatch ignores prefix, digits, case and padding', () {
    expect(normalizeForMatch('[#2] Read a Bible'), 'read a bible');
    expect(normalizeForMatch('Read a Bible 5'), 'read a bible');
    expect(normalizeForMatch('  READ A BIBLE  '), 'read a bible');
    expect(normalizeForMatch('Pray'), isNot(normalizeForMatch('Read')));
  });
}
