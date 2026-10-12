import 'package:timezone/timezone.dart' as tz;

import 'sequence_naming.dart';

/// "What is done?" - the pure rules behind the Notes button that turns the
/// finished work of the previous working day into a grouped checklist.

/// What the rules need to know about one action of that day.
class DiaryAction {
  const DiaryAction({
    required this.id,
    required this.name,
    required this.startAt,
  });

  final String id;
  final String name;
  final DateTime startAt;
}

/// One checklist line: the sub-tags of the name plus its sentence in the past.
class DiaryItem {
  const DiaryItem(this.text);

  /// e.g. `[JBT:DK-9358] Implemented feature.`
  final String text;
}

/// A top-level checklist line: the group tag, with its items below.
class DiaryGroup {
  const DiaryGroup(this.tag, this.items);

  /// e.g. `[Target:Jeremy]`
  final String tag;
  final List<DiaryItem> items;
}

class DiaryResult {
  const DiaryResult({required this.groups, required this.matchedIds});

  final List<DiaryGroup> groups;

  /// EVERY action that qualified (all `[#n]` variants, duplicates included):
  /// they all become Previous actions of the diary action.
  final List<String> matchedIds;

  bool get isEmpty => groups.isEmpty;
}

/// Block codes typed by the user (`KBT, Target:Jeremy`): split on commas and
/// whitespace, lower-cased; empty = no restriction.
List<String> parseBlockCodes(String? text) => [
  for (final c in (text ?? '').split(RegExp(r'[,;\s]+')))
    if (c.trim().isNotEmpty) c.trim().toLowerCase(),
];

final _tagRegex = RegExp(r'\[([^\[\]]+)\]');

/// Bracket tags at the start of [base] (after the optional `[#n]` prefix was
/// removed) and the rest of the name.
({List<String> tags, String rest}) splitTags(String base) {
  final tags = <String>[];
  var rest = base.trimLeft();
  while (true) {
    final m = _tagRegex.matchAsPrefix(rest);
    if (m == null) break;
    tags.add(m.group(1)!.trim());
    rest = rest.substring(m.end).trimLeft();
  }
  return (tags: tags, rest: rest.trim());
}

/// A tag matches a code when it is exactly that code (`KBT:CS-12`) or has
/// that key (`KBT`), ignoring case.
bool tagMatchesCode(String tag, String code) {
  final t = tag.toLowerCase();
  if (t == code) return true;
  final colon = t.indexOf(':');
  return colon > 0 && t.substring(0, colon).trim() == code;
}

/// Builds the checklist from the actions of the previous working day (already
/// restricted to finished, timed ones). An action is kept when it has at least
/// one tag and, if [codes] is not empty, one of its tags matches a code.
/// Same-name actions (`[#1]`, `[#2]`...) are shown once, at the earliest start.
DiaryResult buildDiary(Iterable<DiaryAction> actions, List<String> codes) {
  final sorted = actions.toList()
    ..sort((a, b) => a.startAt.compareTo(b.startAt));
  final matched = <String>[];
  final seen = <String>{};
  final groups = <String, List<DiaryItem>>{};
  final order = <String>[];
  for (final a in sorted) {
    final (_, base) = parseSequencePrefix(a.name);
    final parts = splitTags(base);
    if (parts.tags.isEmpty) continue;
    if (codes.isNotEmpty &&
        !parts.tags.any((t) => codes.any((c) => tagMatchesCode(t, c)))) {
      continue;
    }
    matched.add(a.id);
    if (!seen.add(base.trim().toLowerCase())) continue;

    final groupTag = '[${parts.tags.first}]';
    final subTags = [for (final t in parts.tags.skip(1)) '[$t]'];
    final sentence = parts.rest.isEmpty ? '' : _pastSentence(parts.rest);
    final text = [...subTags, if (sentence.isNotEmpty) sentence].join(' ');
    if (text.isEmpty) continue;
    if (!groups.containsKey(groupTag)) order.add(groupTag);
    groups.putIfAbsent(groupTag, () => []).add(DiaryItem(text));
  }
  return DiaryResult(
    groups: [for (final g in order) DiaryGroup(g, groups[g]!)],
    matchedIds: matched,
  );
}

/// Turns the first word of [rest] into the past tense and ends with a period.
String _pastSentence(String rest) {
  final trimmed = rest.replaceFirst(RegExp(r'[.\s]+$'), '');
  final m = RegExp(r'^(\S+)(.*)$', dotAll: true).firstMatch(trimmed);
  if (m == null) return '';
  return '${pastTense(m.group(1)!)}${m.group(2)}.';
}

const _irregular = {
  'make': 'made',
  'write': 'wrote',
  'run': 'ran',
  'do': 'did',
  'go': 'went',
  'build': 'built',
  'send': 'sent',
  'get': 'got',
  'give': 'gave',
  'take': 'took',
  'find': 'found',
  'read': 'read',
  'set': 'set',
  'put': 'put',
  'meet': 'met',
  'pay': 'paid',
  'buy': 'bought',
  'think': 'thought',
  'speak': 'spoke',
  'begin': 'began',
  'choose': 'chose',
  'hold': 'held',
  'keep': 'kept',
  'lead': 'led',
  'leave': 'left',
  'say': 'said',
  'see': 'saw',
  'sell': 'sold',
  'teach': 'taught',
  'tell': 'told',
  'bring': 'brought',
  'come': 'came',
  'draw': 'drew',
  'drive': 'drove',
  'eat': 'ate',
  'cut': 'cut',
  'learn': 'learned',
};

/// A small English past-tense algorithm (no dictionary of verbs): irregulars
/// from a short list, `-e` -> `-d`, consonant+`y` -> `-ied`, a doubled final
/// consonant for short consonant-vowel-consonant words (stop -> stopped),
/// otherwise `-ed`. Words that already end in `-ed`, acronyms and anything that
/// is not plain Latin letters stay as they are.
String pastTense(String word) {
  if (word.length < 2 || !RegExp(r'^[A-Za-z]+$').hasMatch(word)) return word;
  if (word == word.toUpperCase()) return word; // API, QA
  final lower = word.toLowerCase();
  String match(String past) => word[0] == word[0].toUpperCase()
      ? past[0].toUpperCase() + past.substring(1)
      : past;
  final irregular = _irregular[lower];
  if (irregular != null) return match(irregular);
  if (lower.endsWith('ed')) return word;
  if (lower.endsWith('e')) return '${word}d';
  if (RegExp(r'[^aeiou]y$').hasMatch(lower)) {
    return '${word.substring(0, word.length - 1)}ied';
  }
  if (lower.length <= 4 &&
      RegExp(r'^[^aeiou]{1,2}[aeiou][^aeiouwxy]$').hasMatch(lower)) {
    return '$word${word[word.length - 1]}ed';
  }
  return '${word}ed';
}

/// The Istanbul calendar day (as UTC instants, end exclusive) of the working
/// day before [reference]: the latest day in [workingWeekdays] (ISO 1-7)
/// strictly before the reference's own date. Null when no weekday is enabled.
({DateTime startUtc, DateTime endUtc})? previousWorkingDay(
  DateTime reference,
  Set<int> workingWeekdays,
  tz.Location location,
) {
  if (workingWeekdays.isEmpty) return null;
  final local = tz.TZDateTime.from(reference, location);
  var day = tz.TZDateTime(location, local.year, local.month, local.day);
  for (var i = 0; i < 7; i++) {
    day = tz.TZDateTime(location, day.year, day.month, day.day - 1);
    if (workingWeekdays.contains(day.weekday)) {
      final next = tz.TZDateTime(location, day.year, day.month, day.day + 1);
      return (startUtc: day.toUtc(), endUtc: next.toUtc());
    }
  }
  return null;
}
