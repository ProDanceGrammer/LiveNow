import 'dart:convert';

import '../core/ids.dart';
import '../data/database.dart';
import 'actions_csv.dart';
import 'growth_import.dart' show normalizeDirectionName;

/// What a templates CSV import did.
class TemplateImportResult {
  final int created;

  /// Rows whose name already is a template (or repeats earlier in the file).
  final int skipped;

  /// Direction names in the file that match no existing direction.
  final List<String> unmatchedDirections;

  /// Rows that had Next/Previous cells (templates have no links; ignored).
  final int linksIgnored;

  const TemplateImportResult({
    required this.created,
    required this.skipped,
    required this.unmatchedDirections,
    required this.linksIgnored,
  });
}

/// Turns the Notion actions export into `action_templates` rows (one per
/// distinct name). Writes nothing else: no actions, no action_metrics - a
/// template only touches growth directions once "Use" creates an action.
class TemplateImportService {
  final AppDatabase db;

  TemplateImportService(this.db);

  /// Throws [FormatException] for an unreadable file, before writing.
  Future<TemplateImportResult> importCsv(String csvText) async {
    final parsed = parseActionsCsv(csvText);

    return db.transaction(() async {
      final directionRows = await db
          .customSelect('SELECT id, name FROM metrics')
          .get();
      final directionId = {
        for (final r in directionRows)
          normalizeDirectionName(r.read<String>('name')): r.read<String>('id'),
      };
      final known = directionId.keys.toSet();
      final seen = <String>{
        for (final t in await db.select(db.actionTemplatesTable).get())
          normalizeDirectionName(t.name),
      };

      var created = 0, skipped = 0, linksIgnored = 0;
      final unmatched = <String>{};
      for (final a in parsed.actions) {
        if (a.nextRefs.isNotEmpty || a.prevRefs.isNotEmpty) linksIgnored++;
        if (!seen.add(normalizeDirectionName(a.name))) {
          skipped++;
          continue;
        }
        final metricIds = <String>{};
        for (final n in splitDirectionNames(a.directionsCell, known)) {
          final id = directionId[normalizeDirectionName(n)];
          if (id == null) {
            unmatched.add(n);
          } else {
            metricIds.add(id);
          }
        }
        final start = a.start, end = a.end;
        final minutes = (!a.isAllDay && start != null && end != null)
            ? end.difference(start).inMinutes
            : null;
        await db
            .into(db.actionTemplatesTable)
            .insert(
              ActionTemplatesTableCompanion.insert(
                id: newId(),
                name: a.name,
                payload: jsonEncode({
                  'name': a.name,
                  'isAllDay': a.isAllDay,
                  if (minutes != null && minutes > 0)
                    'estimatedMinutes': minutes,
                  'metricIds': metricIds.toList(),
                }),
              ),
            );
        created++;
      }
      return TemplateImportResult(
        created: created,
        skipped: skipped,
        unmatchedDirections: unmatched.toList(),
        linksIgnored: linksIgnored,
      );
    });
  }
}
