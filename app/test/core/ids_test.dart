import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/ids.dart';

void main() {
  test('deriveId is deterministic, role/index/namespace sensitive, a UUID', () {
    final a = deriveId('job-1', 'tx', 0);
    expect(deriveId('job-1', 'tx', 0), a);
    expect(deriveId('job-1', 'tx'), a);
    expect(deriveId('job-1', 'tx', 1), isNot(a));
    expect(deriveId('job-1', 'cat', 0), isNot(a));
    expect(deriveId('job-2', 'tx', 0), isNot(a));
    expect(
      a,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });
}
