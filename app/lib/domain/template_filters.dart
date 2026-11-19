/// The Templates tab's filters (pure rules; the screen keeps the state).
///
/// [nameText] is a case-insensitive "contains" (Dart, so Cyrillic works).
/// While an average bound is set, a template WITHOUT an average (never run) is
/// hidden. Included directions match when any (or, with [allIncluded], all) of
/// them is linked; excluded ones must not be linked at all.
class TemplateFilters {
  const TemplateFilters({
    this.nameText = '',
    this.minAverage,
    this.maxAverage,
    this.includeIds = const {},
    this.allIncluded = false,
    this.excludeIds = const {},
  });

  final String nameText;

  /// Average-time bounds in minutes, inclusive.
  final int? minAverage;
  final int? maxAverage;
  final Set<String> includeIds;
  final bool allIncluded;
  final Set<String> excludeIds;

  bool get active =>
      nameText.trim().isNotEmpty ||
      minAverage != null ||
      maxAverage != null ||
      includeIds.isNotEmpty ||
      excludeIds.isNotEmpty;

  TemplateFilters copyWith({
    String? nameText,
    int? minAverage,
    bool clearMinAverage = false,
    int? maxAverage,
    bool clearMaxAverage = false,
    Set<String>? includeIds,
    bool? allIncluded,
    Set<String>? excludeIds,
  }) => TemplateFilters(
    nameText: nameText ?? this.nameText,
    minAverage: clearMinAverage ? null : (minAverage ?? this.minAverage),
    maxAverage: clearMaxAverage ? null : (maxAverage ?? this.maxAverage),
    includeIds: includeIds ?? this.includeIds,
    allIncluded: allIncluded ?? this.allIncluded,
    excludeIds: excludeIds ?? this.excludeIds,
  );

  bool matches({
    required String name,
    required int? averageMinutes,
    required Set<String> metricIds,
  }) {
    final q = nameText.trim().toLowerCase();
    if (q.isNotEmpty && !name.toLowerCase().contains(q)) return false;
    if (minAverage != null || maxAverage != null) {
      final a = averageMinutes;
      if (a == null) return false;
      if (minAverage != null && a < minAverage!) return false;
      if (maxAverage != null && a > maxAverage!) return false;
    }
    if (includeIds.isNotEmpty) {
      final ok = allIncluded
          ? includeIds.every(metricIds.contains)
          : includeIds.any(metricIds.contains);
      if (!ok) return false;
    }
    if (excludeIds.any(metricIds.contains)) return false;
    return true;
  }
}
