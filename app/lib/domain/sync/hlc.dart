/// Hybrid-logical-clock stamps as written by the sync triggers:
/// `2026-10-10T12:00:00.123Z-00ab-<device id>` (fixed-width wall time, 4 hex
/// counter digits, device id). Plain string order IS the clock order.
int compareHlc(String a, String b) => a.compareTo(b);

/// The wall-time part and the counter of a stamp, for advancing the local
/// clock past a stamp received from another device.
({String wall, int counter}) parseHlc(String hlc) {
  const wallLength = 24; // 2026-10-10T12:00:00.123Z
  if (hlc.length < wallLength + 5 || hlc[wallLength] != '-') {
    throw FormatException('Not a sync clock stamp', hlc);
  }
  return (
    wall: hlc.substring(0, wallLength),
    counter: int.parse(
      hlc.substring(wallLength + 1, wallLength + 5),
      radix: 16,
    ),
  );
}
