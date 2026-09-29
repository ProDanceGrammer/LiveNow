import 'dart:convert';

import 'growth_rules.dart';

// Reads the Notion export of the growth directions (see
// dev/references/growth_directions.csv). Only the columns that define a
// direction are used; everything Notion computed (auto_weight, auto_progress,
// auto_urgency, when_urgency_counted, the *_count columns, manual_weight,
// parent_item_id) is ignored because the app recomputes it.

/// One direction read from the export.
class ImportedDirection {
  final String pageId;
  final String name;
  final MetricKind kind;
  final MetricWindow? window;
  final double target;
  final bool isMain;

  /// Names (as written in the file) of the directions this one depends on.
  final List<String> dependsOnNames;

  const ImportedDirection({
    required this.pageId,
    required this.name,
    required this.kind,
    required this.window,
    required this.target,
    required this.isMain,
    required this.dependsOnNames,
  });
}

class ParsedGrowthCsv {
  final List<ImportedDirection> directions;

  /// Rows with an empty name (template leftovers), ignored.
  final int skippedBlank;

  /// Names of rows whose metric_data_type isn't understood, ignored.
  final List<String> unsupported;

  const ParsedGrowthCsv({
    required this.directions,
    required this.skippedBlank,
    required this.unsupported,
  });
}

/// Names are the export's join keys, and they mix `'` and `’`; compare them
/// through this.
String normalizeDirectionName(String name) => name.replaceAll('’', "'").trim();

const _requiredColumns = [
  'page_id',
  'objective_name',
  'metric_data_type',
  'numerical_objective',
  'depends_on',
  'improves_count',
];

(MetricKind, MetricWindow?)? _typeOf(String notionType) =>
    switch (notionType.trim()) {
      'Boolean' => (MetricKind.boolean, null),
      'Weekly Done Actions' => (MetricKind.count, MetricWindow.week),
      'Weekly Done Hours' => (MetricKind.hours, MetricWindow.week),
      'Last 30 Days Done Actions' => (MetricKind.count, MetricWindow.month),
      'Last 30 Days Done Hours' => (MetricKind.hours, MetricWindow.month),
      'Last Year Done Actions' => (MetricKind.count, MetricWindow.year),
      'Last 5 Years Done Actions' => (MetricKind.count, MetricWindow.fiveYears),
      _ => null,
    };

/// Parses the export. Throws [FormatException] when a required column is
/// missing, before anything has been changed.
ParsedGrowthCsv parseGrowthDirectionsCsv(String text) {
  final rows = parseCsv(text);
  if (rows.isEmpty) throw const FormatException('The file is empty.');

  final header = rows.first;
  final column = {for (var i = 0; i < header.length; i++) header[i].trim(): i};
  final missing = _requiredColumns.where((c) => !column.containsKey(c));
  if (missing.isNotEmpty) {
    throw FormatException('Missing column(s): ${missing.join(', ')}');
  }
  String cell(List<String> row, String name) {
    final i = column[name]!;
    return i < row.length ? row[i].trim() : '';
  }

  final directions = <ImportedDirection>[];
  final unsupported = <String>[];
  var skippedBlank = 0;

  for (final row in rows.skip(1)) {
    if (row.every((c) => c.trim().isEmpty)) continue;
    final name = cell(row, 'objective_name');
    if (name.isEmpty) {
      skippedBlank++;
      continue;
    }
    final type = _typeOf(cell(row, 'metric_data_type'));
    if (type == null) {
      unsupported.add(name);
      continue;
    }
    final (kind, window) = type;

    final dependsOnCell = cell(row, 'depends_on');
    final dependsOn = dependsOnCell.isEmpty
        ? const <String>[]
        : [for (final n in jsonDecode(dependsOnCell) as List) n.toString()];

    directions.add(
      ImportedDirection(
        pageId: cell(row, 'page_id'),
        name: name,
        kind: kind,
        window: window,
        target: kind == MetricKind.boolean
            ? 1
            : double.tryParse(cell(row, 'numerical_objective')) ?? 1,
        isMain: (int.tryParse(cell(row, 'improves_count')) ?? 0) > 0,
        dependsOnNames: dependsOn,
      ),
    );
  }

  return ParsedGrowthCsv(
    directions: directions,
    skippedBlank: skippedBlank,
    unsupported: unsupported,
  );
}

/// Minimal RFC 4180 reader: optional BOM, CRLF or LF rows, quoted cells with
/// embedded commas, newlines and doubled quotes.
List<List<String>> parseCsv(String input) {
  final text = input.startsWith('﻿') ? input.substring(1) : input;
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      inQuotes = true;
    } else if (c == ',') {
      endField();
    } else if (c == '\n') {
      endRow();
    } else if (c != '\r') {
      field.write(c);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}
