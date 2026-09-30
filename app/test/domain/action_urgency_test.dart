import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/action_urgency.dart';
import 'package:livenow/domain/growth_rules.dart';

MetricStat _s(double u) => MetricStat(fact: 0, progress: 0, urgency: u);

void main() {
  final stats = {'a': _s(1000), 'b': _s(-90), 'c': _s(5.5)};

  test('sums urgencies, negatives included', () {
    expect(actionUrgency(['a', 'b'], stats), 910);
    expect(actionUrgency(['b'], stats), -90);
  });

  test('ids without stats are skipped; none known => null', () {
    expect(actionUrgency(['a', 'zzz'], stats), 1000);
    expect(actionUrgency(['zzz'], stats), isNull);
    expect(actionUrgency(const [], stats), isNull);
  });

  test('actionUrgencies groups by action; unlinked actions are absent', () {
    final m = actionUrgencies([
      ('a', 'x1'),
      ('b', 'x1'),
      ('c', 'x2'),
      ('zzz', 'x3'),
    ], stats);
    expect(m, {'x1': 910, 'x2': 5.5});
    expect(m.containsKey('x3'), isFalse);
    expect(m.containsKey('x4'), isFalse);
  });
}
