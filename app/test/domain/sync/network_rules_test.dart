import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/sync/network_rules.dart';

void main() {
  group('isPrivateAddress', () {
    test('accepts home, hotspot, VPN and loopback addresses', () {
      for (final a in [
        '127.0.0.1',
        '10.2.0.2',
        '192.168.1.104',
        '172.16.0.1',
        '172.20.10.2', // iPhone hotspot
        '172.31.255.254',
        '169.254.3.4',
        '100.64.0.1', // Tailscale range
        '100.127.255.255',
        '::1',
        'fd12:3456::1',
        'fe80::1',
        '::ffff:192.168.1.5',
      ]) {
        expect(isPrivateAddress(a), isTrue, reason: a);
      }
    });

    test('refuses public and malformed addresses', () {
      for (final a in [
        '8.8.8.8',
        '203.0.113.1',
        '172.32.0.1',
        '172.15.0.1',
        '100.63.0.1',
        '100.128.0.1',
        '192.169.1.1',
        '::ffff:8.8.8.8',
        '2001:db8::1',
        '256.1.1.1',
        '1.2.3',
        '',
        'example.com',
      ]) {
        expect(isPrivateAddress(a), isFalse, reason: a);
      }
    });
  });

  group('isAllowedPairingHost', () {
    test('allows private addresses and local names', () {
      for (final h in ['192.168.1.5', 'MYPC', 'mypc.local', 'pc.tail1234.ts.net']) {
        expect(isAllowedPairingHost(h), isTrue, reason: h);
      }
    });

    test('refuses public addresses and public-looking names', () {
      for (final h in ['8.8.8.8', 'evil.example.com', 'a@b', 'x/y', '']) {
        expect(isAllowedPairingHost(h), isFalse, reason: h);
      }
    });
  });

  group('FailureThrottle', () {
    test('bans a source after repeated failures, then lets it back in', () {
      var now = DateTime(2026, 1, 1, 12);
      final t = FailureThrottle(
        maxFailures: 3,
        ban: const Duration(minutes: 5),
        now: () => now,
      );
      t.failed('a');
      t.failed('a');
      expect(t.isBanned('a'), isFalse);
      t.failed('a');
      expect(t.isBanned('a'), isTrue);
      expect(t.isBanned('b'), isFalse);
      now = now.add(const Duration(minutes: 6));
      expect(t.isBanned('a'), isFalse);
    });

    test('old failures expire and a success clears the count', () {
      var now = DateTime(2026, 1, 1, 12);
      final t = FailureThrottle(maxFailures: 3, now: () => now);
      t.failed('a');
      t.failed('a');
      now = now.add(const Duration(minutes: 2));
      t.failed('a'); // the first two are out of the window
      expect(t.isBanned('a'), isFalse);
      t.failed('a');
      t.succeeded('a');
      t.failed('a');
      expect(t.isBanned('a'), isFalse);
    });
  });
}
