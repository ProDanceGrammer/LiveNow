// Pure network rules of the sync: who may talk to the PC's server and which
// hosts a phone may be told to connect to. Both only accept addresses that
// live on a local, VPN or hotspot network, never a public one.

/// True when [address] is a literal IPv4/IPv6 address on a private network:
/// loopback, 10/8, 172.16/12, 192.168/16 (home Wi-Fi, phone hotspots),
/// 169.254/16 link-local, 100.64/10 (Tailscale / carrier NAT), IPv6 loopback,
/// unique-local fc00::/7 and link-local fe80::/10. A host NAME is not an
/// address: use [isLocalHostName] for those.
bool isPrivateAddress(String address) {
  final v4 = _parseV4(address);
  if (v4 != null) {
    final a = v4[0], b = v4[1];
    return a == 127 ||
        a == 10 ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168) ||
        (a == 169 && b == 254) ||
        (a == 100 && b >= 64 && b <= 127);
  }
  final lower = address.toLowerCase();
  if (lower == '::1') return true;
  // IPv4-mapped IPv6 (::ffff:192.168.1.5) is judged as the IPv4 it carries.
  final mapped = RegExp(r'^::ffff:(\d+\.\d+\.\d+\.\d+)$').firstMatch(lower);
  if (mapped != null) return isPrivateAddress(mapped.group(1)!);
  if (!lower.contains(':')) return false;
  final first = int.tryParse(lower.split(':').first, radix: 16);
  if (first == null) return false;
  return (first & 0xfe00) == 0xfc00 || (first & 0xffc0) == 0xfe80;
}

/// True for a host NAME that can only be resolved on the local network: a
/// single label ("MYPC") or one ending in .local / .lan / .home / .internal /
/// .ts.net. A dotted public-looking name is refused.
bool isLocalHostName(String host) {
  final h = host.toLowerCase();
  if (h.isEmpty || h.contains(' ') || h.contains('/') || h.contains('@')) {
    return false;
  }
  if (!h.contains('.')) return true;
  return const ['.local', '.lan', '.home', '.internal', '.ts.net'].any(h.endsWith);
}

/// Whether a phone may connect to [host] (an address or name from a QR code).
bool isAllowedPairingHost(String host) =>
    isPrivateAddress(host) || (!_isIpLiteral(host) && isLocalHostName(host));

bool _isIpLiteral(String s) => _parseV4(s) != null || s.contains(':');

List<int>? _parseV4(String s) {
  final parts = s.split('.');
  if (parts.length != 4) return null;
  final out = <int>[];
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null || n < 0 || n > 255 || p.length > 3) return null;
    out.add(n);
  }
  return out;
}

/// Counts failed attempts per source and bans a source that keeps failing, so
/// a stranger on a shared network cannot hammer the server or burn the pairing
/// window for everybody. A success clears the count.
class FailureThrottle {
  FailureThrottle({
    this.maxFailures = 8,
    this.window = const Duration(minutes: 1),
    this.ban = const Duration(minutes: 5),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final int maxFailures;
  final Duration window;
  final Duration ban;
  final DateTime Function() _now;

  final _failures = <String, List<DateTime>>{};
  final _bannedUntil = <String, DateTime>{};

  bool isBanned(String source) {
    final until = _bannedUntil[source];
    if (until == null) return false;
    if (_now().isBefore(until)) return true;
    _bannedUntil.remove(source);
    _failures.remove(source);
    return false;
  }

  void failed(String source) {
    final now = _now();
    final list = (_failures[source] ??= <DateTime>[])
      ..removeWhere((t) => now.difference(t) > window)
      ..add(now);
    if (list.length >= maxFailures) {
      _bannedUntil[source] = now.add(ban);
      _failures.remove(source);
    }
    // Bound the memory a scan of many addresses can use.
    if (_failures.length > 2048) _failures.clear();
    if (_bannedUntil.length > 2048) _bannedUntil.clear();
  }

  void succeeded(String source) => _failures.remove(source);
}
