import 'package:timezone/timezone.dart' as tz;

import '../core/settings.dart';
import 'growth_import.dart' show normalizeDirectionName, parseCsv;

// Reads the Notion export of actions (see dev/data/actions/*.csv): columns
// `Name`, `Datetime`, `Next actions and time`, `Previous actions and time`,
// `Growth Direction`. Pure apart from the Istanbul wall-clock -> UTC
// conversion, which needs the timezone database to be initialised
// (initPostponeTimeZoneData).

/// A reference to another action from a Next/Previous cell: its name and the
/// time it was scheduled at (UTC; null when the entry carried no time).
class ActionRef {
  final String name;
  final DateTime? start;
  final DateTime? end;

  const ActionRef(this.name, this.start, this.end);

  @override
  String toString() => 'ActionRef($name, $start)';
}

/// One action row of the export.
class ParsedAction {
  final String name;

  /// UTC. For an all-day action: local midnight of that day.
  final DateTime? start;
  final DateTime? end;
  final bool isAllDay;
  final List<ActionRef> nextRefs;
  final List<ActionRef> prevRefs;

  /// The raw `Growth Direction` cell; split it against the known directions
  /// with [splitDirectionNames].
  final String directionsCell;

  const ParsedAction({
    required this.name,
    required this.start,
    required this.end,
    required this.isAllDay,
    required this.nextRefs,
    required this.prevRefs,
    required this.directionsCell,
  });
}

class ParsedActionsCsv {
  final List<ParsedAction> actions;

  /// Rows with an empty name, ignored.
  final int skippedBlank;

  /// Rows whose `Datetime` cell couldn't be read (imported unscheduled).
  final List<String> badDates;

  const ParsedActionsCsv({
    required this.actions,
    required this.skippedBlank,
    required this.badDates,
  });
}

const _months = {
  'January': 1, 'February': 2, 'March': 3, 'April': 4, 'May': 5,
  'June': 6, 'July': 7, 'August': 8, 'September': 9, 'October': 10,
  'November': 11, 'December': 12, //
};

/// Local (Istanbul) wall-clock -> UTC instant.
DateTime localWallToUtc(int y, int mo, int d, [int h = 0, int mi = 0]) =>
    tz.TZDateTime(
      tz.getLocation(AppSettings.timeZoneName),
      y,
      mo,
      d,
      h,
      mi,
    ).toUtc();

/// Parses the export. Throws [FormatException] when `Name` is missing.
ParsedActionsCsv parseActionsCsv(String text) {
  final rows = parseCsv(text);
  if (rows.isEmpty) throw const FormatException('The file is empty.');
  final column = {
    for (var i = 0; i < rows.first.length; i++) rows.first[i].trim(): i,
  };
  if (!column.containsKey('Name')) {
    throw const FormatException('Missing column: Name');
  }
  String cell(List<String> row, String name) {
    final i = column[name];
    return i == null || i >= row.length ? '' : row[i].trim();
  }

  final actions = <ParsedAction>[];
  final badDates = <String>[];
  var skippedBlank = 0;
  for (final row in rows.skip(1)) {
    if (row.every((c) => c.trim().isEmpty)) continue;
    final name = cell(row, 'Name');
    if (name.isEmpty) {
      skippedBlank++;
      continue;
    }
    final dt = parseDatetimeCell(cell(row, 'Datetime'));
    if (dt == null && cell(row, 'Datetime').isNotEmpty) badDates.add(name);
    actions.add(
      ParsedAction(
        name: name,
        start: dt?.start,
        end: dt?.end,
        isAllDay: dt?.isAllDay ?? false,
        nextRefs: parseRefs(cell(row, 'Next actions and time')),
        prevRefs: parseRefs(cell(row, 'Previous actions and time')),
        directionsCell: cell(row, 'Growth Direction'),
      ),
    );
  }
  return ParsedActionsCsv(
    actions: actions,
    skippedBlank: skippedBlank,
    badDates: badDates,
  );
}

final _datetimeRe = RegExp(
  r'^(\d{1,2})/(\d{1,2})/(\d{4})'
  r'(?:\s+(\d{1,2}):(\d{2})(?:\s*→\s*(?:(\d{1,2})/(\d{1,2})/(\d{4})\s+)?(\d{1,2}):(\d{2}))?)?$',
);

/// `DD/MM/YYYY` (all-day) or `DD/MM/YYYY H:mm → [DD/MM/YYYY ]H:mm` (end optional); null
/// when the cell is empty or unreadable.
({DateTime start, DateTime? end, bool isAllDay})? parseDatetimeCell(
  String cell,
) {
  final m = _datetimeRe.firstMatch(cell.trim());
  if (m == null) return null;
  final d = int.parse(m[1]!), mo = int.parse(m[2]!), y = int.parse(m[3]!);
  if (m[4] == null) {
    return (start: localWallToUtc(y, mo, d), end: null, isAllDay: true);
  }
  final start = localWallToUtc(y, mo, d, int.parse(m[4]!), int.parse(m[5]!));
  DateTime? end;
  if (m[9] != null) {
    // The end may carry its own date (`23:00 → 04/10/2026 8:00`).
    end = localWallToUtc(
      m[8] != null ? int.parse(m[8]!) : y,
      m[7] != null ? int.parse(m[7]!) : mo,
      m[6] != null ? int.parse(m[6]!) : d,
      int.parse(m[9]!),
      int.parse(m[10]!),
    );
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
  }
  return (start: start, end: end, isAllDay: false);
}

const _mon =
    'January|February|March|April|May|June|July|August|September|October|'
    'November|December';
final _stampRe = RegExp(
  '($_mon) '
  r'(\d{1,2}), (\d{4}) (\d{1,2}):(\d{2}) (AM|PM)'
  '(?: → (?:($_mon) '
  r'(\d{1,2}), (\d{4}) )?(\d{1,2}):(\d{2}) (AM|PM))?',
);

int _hour24(String h, String ampm) =>
    int.parse(h) % 12 + (ampm == 'PM' ? 12 : 0);

/// Splits a Next/Previous cell: `Name Month D, YYYY h:mm AM → h:mm PM` entries
/// joined by commas. Names may contain commas, so each entry is found by its
/// trailing date stamp; text after the last stamp (no stamp) is a name-only
/// reference.
List<ActionRef> parseRefs(String cell) {
  final refs = <ActionRef>[];
  var from = 0;
  String clean(String s) => s.replaceAll(RegExp(r'^[\s,]+|[\s,]+$'), '');
  for (final m in _stampRe.allMatches(cell)) {
    final name = clean(cell.substring(from, m.start));
    from = m.end;
    if (name.isEmpty) continue;
    final start = localWallToUtc(
      int.parse(m[3]!),
      _months[m[1]]!,
      int.parse(m[2]!),
      _hour24(m[4]!, m[6]!),
      int.parse(m[5]!),
    );
    DateTime? end;
    if (m[10] != null) {
      end = localWallToUtc(
        m[9] != null ? int.parse(m[9]!) : int.parse(m[3]!),
        m[7] != null ? _months[m[7]]! : _months[m[1]]!,
        m[8] != null ? int.parse(m[8]!) : int.parse(m[2]!),
        _hour24(m[10]!, m[12]!),
        int.parse(m[11]!),
      );
      if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    }
    refs.add(ActionRef(name, start, end));
  }
  final tail = clean(cell.substring(from));
  if (tail.isNotEmpty) refs.add(ActionRef(tail, null, null));
  return refs;
}

/// Splits a `Growth Direction` cell into names, greedily preferring the
/// longest comma-joined run that is a known direction (names can contain
/// commas). [known] holds [normalizeDirectionName]d names. A part that matches
/// nothing is returned alone (trimmed) so the caller can report it.
List<String> splitDirectionNames(String cell, Set<String> known) {
  if (cell.trim().isEmpty) return const [];
  final parts = cell.split(',');
  final out = <String>[];
  var i = 0;
  while (i < parts.length) {
    var matched = 0;
    for (var j = parts.length; j > i; j--) {
      final joined = parts.sublist(i, j).join(',');
      if (known.contains(normalizeDirectionName(joined))) {
        out.add(joined.trim());
        matched = j - i;
        break;
      }
    }
    if (matched == 0) {
      final single = parts[i].trim();
      if (single.isNotEmpty) out.add(single);
      matched = 1;
    }
    i += matched;
  }
  return out;
}
