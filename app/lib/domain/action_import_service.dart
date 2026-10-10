import 'package:drift/drift.dart';

import '../core/time_codec.dart';
import '../data/database.dart';
import 'action_service.dart';
import 'actions_csv.dart';
import 'dependency_service.dart';
import 'growth_import.dart' show normalizeDirectionName;

/// What an actions CSV import did.
class ActionImportResult {
  final int created;

  /// Rows whose name + start already existed (nothing written for them).
  final int skippedDuplicates;
  final int edgesCreated;

  /// Direction names in the file that match no existing direction.
  final List<String> unmatchedDirections;

  /// Next/Previous references that match no action, "Row -> Ref (date)".
  final List<String> unresolvedRefs;

  /// Edges refused (cycle / self-link), "A -> B".
  final List<String> rejectedEdges;
  final int skippedBlank;

  /// All-day actions whose done flag the `Done` column set (new rows marked
  /// done, and existing rows whose flag it changed).
  final int doneApplied;

  /// `Done` values on timed actions, ignored: those are done by their end time.
  final int doneIgnoredTimed;

  const ActionImportResult({
    required this.created,
    required this.skippedDuplicates,
    required this.edgesCreated,
    required this.unmatchedDirections,
    required this.unresolvedRefs,
    required this.rejectedEdges,
    this.skippedBlank = 0,
    this.doneApplied = 0,
    this.doneIgnoredTimed = 0,
  });
}

/// Imports the Notion actions export: creates the actions, links their
/// growth directions and next/previous edges. One transaction; re-importing
/// the same file creates nothing new (rows are matched by name + start). An
/// optional `Done` column (Yes/No) sets the manual done flag of ALL-DAY actions,
/// also on rows that already exist (the file is the source for that flag).
class ActionImportService {
  final AppDatabase db;
  final ActionService actions;
  final DependencyService dependencies;

  ActionImportService(this.db)
    : actions = ActionService(db),
      dependencies = DependencyService(db);

  static String _key(String name, DateTime? start) =>
      '$name|${start == null ? '' : dateTimeToDb(start)!.substring(0, 16)}';

  /// Throws [FormatException] for an unreadable file, before writing.
  Future<ActionImportResult> importCsv(String csvText) async {
    final parsed = parseActionsCsv(csvText);

    return db.transaction(() async {
      final directionRows = await db
          .customSelect('SELECT id, name FROM metrics')
          .get();
      final directionId = {
        for (final r in directionRows)
          normalizeDirectionName(r.read<String>('name')): r.read<String>('id'),
      };
      final knownDirections = directionId.keys.toSet();
      final existingRows = await db
          .customSelect('SELECT id, name, start_at FROM actions')
          .get();
      // name+start (minute) -> id; and name -> ids for start-less references.
      final byKey = <String, String>{};
      final byName = <String, List<String>>{};
      for (final r in existingRows) {
        final name = r.read<String>('name');
        final id = r.read<String>('id');
        byKey.putIfAbsent(
          _key(name, dateTimeFromDb(r.read<String?>('start_at'))),
          () => id,
        );
        byName.putIfAbsent(name, () => []).add(id);
      }

      var created = 0, skipped = 0, doneApplied = 0, doneIgnoredTimed = 0;
      final unmatched = <String>{};
      final rowIds = <String>[]; // id per parsed action (new or existing)
      for (final a in parsed.actions) {
        final key = _key(a.name, a.start);
        final known = byKey[key];
        if (known != null) {
          skipped++;
          rowIds.add(known);
          if (a.done != null) {
            if (!a.isAllDay) {
              doneIgnoredTimed++;
            } else if (await _applyDone(known, a.done!)) {
              doneApplied++;
            }
          }
          continue;
        }
        final metricIds = <String>{};
        for (final n in splitDirectionNames(
          a.directionsCell,
          knownDirections,
        )) {
          final id = directionId[normalizeDirectionName(n)];
          if (id == null) {
            unmatched.add(n);
          } else {
            metricIds.add(id);
          }
        }
        final id = await actions.createAction(
          name: a.name,
          startAt: a.start,
          endAt: a.end,
          isAllDay: a.isAllDay,
          metricIds: metricIds.toList(),
        );
        created++;
        if (a.done != null) {
          if (!a.isAllDay) {
            doneIgnoredTimed++;
          } else if (await _applyDone(id, a.done!)) {
            doneApplied++;
          }
        }
        byKey[key] = id;
        byName.putIfAbsent(a.name, () => []).add(id);
        rowIds.add(id);
      }

      String? resolve(ActionRef ref) {
        if (ref.start != null) return byKey[_key(ref.name, ref.start)];
        final ids = byName[ref.name];
        return ids != null && ids.length == 1 ? ids.single : null;
      }

      final seen = <String>{};
      final unresolved = <String>[];
      final rejected = <String>[];
      var edges = 0;

      Future<void> edge(String from, String to, String label) async {
        if (!seen.add('$from>$to')) return;
        final exists =
            await (db.select(db.actionDependenciesTable)..where(
                  (t) =>
                      t.predecessorId.equals(from) & t.successorId.equals(to),
                ))
                .getSingleOrNull();
        if (exists != null) return;
        try {
          await dependencies.addDependency(
            predecessorId: from,
            successorId: to,
          );
          edges++;
        } on DependencyCycleException {
          rejected.add(label);
        } on ArgumentError {
          rejected.add(label);
        }
      }

      for (var i = 0; i < parsed.actions.length; i++) {
        final a = parsed.actions[i];
        final me = rowIds[i];
        for (final (refs, isNext) in [
          (a.nextRefs, true),
          (a.prevRefs, false),
        ]) {
          for (final ref in refs) {
            final other = resolve(ref);
            if (other == null) {
              final day = ref.start == null
                  ? ''
                  : ' (${dateTimeToDb(ref.start)!.substring(0, 10)})';
              unresolved.add('${a.name} -> ${ref.name}$day');
              continue;
            }
            if (isNext) {
              await edge(me, other, '${a.name} -> ${ref.name}');
            } else {
              await edge(other, me, '${ref.name} -> ${a.name}');
            }
          }
        }
      }

      return ActionImportResult(
        created: created,
        skippedDuplicates: skipped,
        edgesCreated: edges,
        unmatchedDirections: unmatched.toList()..sort(),
        unresolvedRefs: unresolved,
        rejectedEdges: rejected,
        skippedBlank: parsed.skippedBlank,
        doneApplied: doneApplied,
        doneIgnoredTimed: doneIgnoredTimed,
      );
    });
  }

  /// Sets the manual done flag of an ALL-DAY action (like `toggleDone`: the
  /// completion time is set or cleared with it). Returns whether anything
  /// changed; a timed action or an unchanged flag is left alone.
  Future<bool> _applyDone(String id, bool done) async {
    final row = await db
        .customSelect(
          'SELECT done, is_all_day FROM actions WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .getSingleOrNull();
    if (row == null || !row.read<bool>('is_all_day')) return false;
    if (row.read<bool>('done') == done) return false;
    final nowText = dateTimeToDb(DateTime.now())!;
    await (db.update(db.actionsTable)..where((t) => t.id.equals(id))).write(
      ActionsTableCompanion(
        done: Value(done),
        completedAt: Value(done ? nowText : null),
        updatedAt: Value(nowText),
      ),
    );
    return true;
  }
}
