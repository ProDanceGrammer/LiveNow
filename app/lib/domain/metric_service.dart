import 'package:drift/drift.dart';

import '../core/ids.dart';
import '../data/database.dart';
import 'growth_import.dart';
import 'growth_rules.dart';

/// Thrown when a direction's relations would make the graph loop back on
/// itself (weights and progress need it acyclic).
class MetricCycleException implements Exception {
  const MetricCycleException();

  @override
  String toString() => 'That would make the growth directions loop.';
}

/// Everything [MetricService.deleteMetric] removed, for
/// [MetricService.undoDelete].
class MetricDeleteUndo {
  final Metric metric;
  final List<MetricDependency> edges;
  final List<ActionMetric> links;

  const MetricDeleteUndo({
    required this.metric,
    required this.edges,
    required this.links,
  });
}

class ImportSummary {
  final int directions;
  final int relations;
  final int skippedBlank;
  final List<String> unsupported;

  /// Relation names that matched no direction in the file.
  final List<String> unresolved;

  const ImportSummary({
    required this.directions,
    required this.relations,
    required this.skippedBlank,
    required this.unsupported,
    required this.unresolved,
  });
}

/// Create/edit/delete growth directions and their relations, keep the derived
/// weights current, and import the Notion export.
/// Result of [MetricService.applyIcons].
class IconApplySummary {
  final int matched;
  final List<String> unmatched;
  const IconApplySummary({required this.matched, required this.unmatched});
}

class MetricService {
  final AppDatabase db;

  MetricService(this.db);

  /// Creates ([id] null) or updates a direction and replaces all its
  /// relations: it depends on [dependsOnIds], and leads to [leadsToIds]
  /// (i.e. those depend on it). Returns its id. Throws
  /// [MetricCycleException] without changing anything if the result would
  /// contain a loop.
  Future<String> saveMetric({
    String? id,
    required String name,
    required MetricKind kind,
    MetricWindow? window,
    double target = 1,
    bool isMain = false,
    Value<String?> icon = const Value.absent(),
    List<String> dependsOnIds = const [],
    List<String> leadsToIds = const [],
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('A direction needs a name.');
    if (kind != MetricKind.boolean && window == null) {
      throw ArgumentError('A count/hours direction needs a time window.');
    }
    final metricId = id ?? newId();
    final depends = {...dependsOnIds}..remove(metricId);
    final leads = {...leadsToIds}..remove(metricId);

    return db.transaction(() async {
      final existing = await db.select(db.metricDependenciesTable).get();
      final graph = GrowthGraph([
        for (final e in existing)
          if (e.metricId != metricId && e.dependsOnId != metricId)
            (metricId: e.metricId, dependsOnId: e.dependsOnId),
        for (final d in depends) (metricId: metricId, dependsOnId: d),
        for (final l in leads) (metricId: l, dependsOnId: metricId),
      ]);
      if (graph.hasCycle) throw const MetricCycleException();

      await db
          .into(db.metricsTable)
          .insertOnConflictUpdate(
            MetricsTableCompanion(
              id: Value(metricId),
              name: Value(trimmed),
              kind: Value(kind.dbValue),
              timeWindow: Value(
                kind == MetricKind.boolean ? null : window!.dbValue,
              ),
              target: Value(kind == MetricKind.boolean ? 1 : target),
              isMain: Value(isMain),
              icon: icon,
            ),
          );

      await (db.delete(db.metricDependenciesTable)..where(
            (t) => t.metricId.equals(metricId) | t.dependsOnId.equals(metricId),
          ))
          .go();
      for (final d in depends) {
        await _insertEdge(metricId, d);
      }
      for (final l in leads) {
        await _insertEdge(l, metricId);
      }

      await recomputeWeights();
      return metricId;
    });
  }

  /// What [id] depends on and what it leads to, for the edit dialog.
  Future<({Set<String> dependsOn, Set<String> leadsTo})> relationsOf(
    String id,
  ) async {
    final edges = await (db.select(
      db.metricDependenciesTable,
    )..where((t) => t.metricId.equals(id) | t.dependsOnId.equals(id))).get();
    return (
      dependsOn: {
        for (final e in edges)
          if (e.metricId == id) e.dependsOnId,
      },
      leadsTo: {
        for (final e in edges)
          if (e.dependsOnId == id) e.metricId,
      },
    );
  }

  /// Deletes a direction with its relations and the links from actions, and
  /// returns what was removed so [undoDelete] can restore it.
  Future<MetricDeleteUndo> deleteMetric(String id) {
    return db.transaction(() async {
      final metric = await (db.select(
        db.metricsTable,
      )..where((t) => t.id.equals(id))).getSingle();
      final edges = await (db.select(
        db.metricDependenciesTable,
      )..where((t) => t.metricId.equals(id) | t.dependsOnId.equals(id))).get();
      final links = await (db.select(
        db.actionMetricsTable,
      )..where((t) => t.metricId.equals(id))).get();

      await (db.delete(
        db.metricDependenciesTable,
      )..where((t) => t.metricId.equals(id) | t.dependsOnId.equals(id))).go();
      await (db.delete(
        db.actionMetricsTable,
      )..where((t) => t.metricId.equals(id))).go();
      await (db.delete(db.metricsTable)..where((t) => t.id.equals(id))).go();

      await recomputeWeights();
      return MetricDeleteUndo(metric: metric, edges: edges, links: links);
    });
  }

  /// Restores a deleted direction. Relations to directions deleted in the
  /// meantime, and links from actions deleted in the meantime, are skipped.
  Future<void> undoDelete(MetricDeleteUndo undo) {
    return db.transaction(() async {
      await db.into(db.metricsTable).insert(undo.metric);

      final metricIds = (await db.select(db.metricsTable).get())
          .map((m) => m.id)
          .toSet();
      for (final edge in undo.edges) {
        if (metricIds.contains(edge.metricId) &&
            metricIds.contains(edge.dependsOnId)) {
          await db.into(db.metricDependenciesTable).insert(edge);
        }
      }
      final actionIds = (await db.select(db.actionsTable).get())
          .map((a) => a.id)
          .toSet();
      for (final link in undo.links) {
        if (actionIds.contains(link.actionId)) {
          await db.into(db.actionMetricsTable).insert(link);
        }
      }

      await recomputeWeights();
    });
  }

  /// Rewrites the derived `importance_level` and `weight` of every direction
  /// from the graph and the main flags (see [importanceLevels] and
  /// [directionWeights]); only rows whose values changed are written.
  Future<void> recomputeWeights() {
    return db.transaction(() async {
      final rows = await db.select(db.metricsTable).get();
      final edges = await db.select(db.metricDependenciesTable).get();
      final graph = GrowthGraph([
        for (final e in edges)
          (metricId: e.metricId, dependsOnId: e.dependsOnId),
      ]);
      final ids = rows.map((r) => r.id).toList();
      final mains = {
        for (final r in rows)
          if (r.isMain) r.id,
      };
      final levels = importanceLevels(ids, mains, graph);
      final weights = directionWeights(ids, mains, graph, levels);

      for (final r in rows) {
        final level = levels[r.id]!;
        final weight = weights[r.id]!;
        if (r.importanceLevel == level && r.weight == weight) continue;
        await (db.update(
          db.metricsTable,
        )..where((t) => t.id.equals(r.id))).write(
          MetricsTableCompanion(
            importanceLevel: Value(level),
            weight: Value(weight),
          ),
        );
      }
    });
  }

  /// Replaces ALL directions, their relations and the actions' links to them
  /// with the ones in the Notion export [csvText]. The text is parsed before
  /// anything is deleted, so a malformed file leaves the data untouched.
  Future<ImportSummary> importGrowthDirections(String csvText) async {
    final parsed = parseGrowthDirectionsCsv(csvText);

    return db.transaction(() async {
      // Icons are set separately (see applyIcons), so carry them over by name.
      final iconByName = {
        for (final m in await db.select(db.metricsTable).get())
          if (m.icon != null) normalizeDirectionName(m.name): m.icon!,
      };
      await db.delete(db.actionMetricsTable).go();
      await db.delete(db.metricDependenciesTable).go();
      await db.delete(db.metricsTable).go();

      final idByName = <String, String>{};
      final ids = <String>[];
      for (final d in parsed.directions) {
        final id = newId();
        ids.add(id);
        idByName[normalizeDirectionName(d.name)] = id;
      }
      await db.batch((batch) {
        batch.insertAll(db.metricsTable, [
          for (var i = 0; i < parsed.directions.length; i++)
            MetricsTableCompanion.insert(
              id: ids[i],
              name: parsed.directions[i].name,
              kind: Value(parsed.directions[i].kind.dbValue),
              timeWindow: Value(parsed.directions[i].window?.dbValue),
              target: Value(parsed.directions[i].target),
              isMain: Value(parsed.directions[i].isMain),
              icon: Value(
                iconByName[normalizeDirectionName(parsed.directions[i].name)],
              ),
            ),
        ]);
      });

      final unresolved = <String>{};
      final edges = <(String, String)>{};
      for (var i = 0; i < parsed.directions.length; i++) {
        for (final name in parsed.directions[i].dependsOnNames) {
          final target = idByName[normalizeDirectionName(name)];
          if (target == null) {
            unresolved.add(name);
          } else if (target != ids[i]) {
            edges.add((ids[i], target));
          }
        }
      }
      await db.batch((batch) {
        batch.insertAll(db.metricDependenciesTable, [
          for (final (metricId, dependsOnId) in edges)
            MetricDependenciesTableCompanion.insert(
              id: newId(),
              metricId: metricId,
              dependsOnId: dependsOnId,
            ),
        ]);
      });

      await recomputeWeights();
      return ImportSummary(
        directions: parsed.directions.length,
        relations: edges.length,
        skippedBlank: parsed.skippedBlank,
        unsupported: parsed.unsupported,
        unresolved: unresolved.toList(),
      );
    });
  }

  /// Sets the icon of every direction whose (normalized) name is a key of
  /// [iconsByName]. Returns the names that matched no direction.
  Future<IconApplySummary> applyIcons(Map<String, String> iconsByName) {
    return db.transaction(() async {
      final rows = await db.select(db.metricsTable).get();
      final byName = {for (final m in rows) normalizeDirectionName(m.name): m};
      var matched = 0;
      final unmatched = <String>[];
      for (final e in iconsByName.entries) {
        final row = byName[normalizeDirectionName(e.key)];
        if (row == null) {
          unmatched.add(e.key);
          continue;
        }
        matched++;
        await (db.update(db.metricsTable)..where((t) => t.id.equals(row.id)))
            .write(MetricsTableCompanion(icon: Value(e.value)));
      }
      return IconApplySummary(matched: matched, unmatched: unmatched);
    });
  }

  /// Stores where nodes sit on the Mindmap ([positions]: id -> (x, y)).
  Future<void> savePositions(Map<String, (double, double)> positions) {
    return db.batch((batch) {
      for (final e in positions.entries) {
        batch.update(
          db.metricsTable,
          MetricsTableCompanion(
            posX: Value(e.value.$1),
            posY: Value(e.value.$2),
          ),
          where: (t) => t.id.equals(e.key),
        );
      }
    });
  }

  /// Puts positions back exactly as they were ([savePositions] can't write
  /// the nulls of nodes that had not been placed yet). One batch.
  Future<void> restorePositions(Map<String, (double?, double?)> positions) {
    return db.batch((batch) {
      for (final e in positions.entries) {
        batch.update(
          db.metricsTable,
          MetricsTableCompanion(
            posX: Value<double?>(e.value.$1),
            posY: Value<double?>(e.value.$2),
          ),
          where: (t) => t.id.equals(e.key),
        );
      }
    });
  }

  /// Forgets all Mindmap positions (the next open lays the map out again).
  Future<void> clearPositions() => db
      .update(db.metricsTable)
      .write(const MetricsTableCompanion(posX: Value(null), posY: Value(null)));

  /// [fromId] leads to [toId] (so [toId] depends on [fromId]). A duplicate is
  /// a no-op; a link that would close a loop throws [MetricCycleException].
  Future<void> addRelation({required String fromId, required String toId}) {
    if (fromId == toId) {
      throw ArgumentError('A direction cannot lead to itself.');
    }
    return db.transaction(() async {
      final existing = await db.select(db.metricDependenciesTable).get();
      if (existing.any((e) => e.metricId == toId && e.dependsOnId == fromId)) {
        return;
      }
      final graph = GrowthGraph([
        for (final e in existing)
          (metricId: e.metricId, dependsOnId: e.dependsOnId),
        (metricId: toId, dependsOnId: fromId),
      ]);
      if (graph.hasCycle) throw const MetricCycleException();
      await _insertEdge(toId, fromId);
      await recomputeWeights();
    });
  }

  /// Removes "[fromId] leads to [toId]". Undo with [addRelation].
  Future<void> removeRelation({required String fromId, required String toId}) {
    return db.transaction(() async {
      await (db.delete(db.metricDependenciesTable)..where(
            (t) => t.metricId.equals(toId) & t.dependsOnId.equals(fromId),
          ))
          .go();
      await recomputeWeights();
    });
  }

  /// Links [actionId] to [metricId]. A no-op when the pair is already linked.
  Future<void> linkAction(String actionId, String metricId) {
    return db.transaction(() async {
      final exists =
          await (db.select(db.actionMetricsTable)..where(
                (t) => t.actionId.equals(actionId) & t.metricId.equals(metricId),
              ))
              .get();
      if (exists.isNotEmpty) return;
      await db
          .into(db.actionMetricsTable)
          .insert(
            ActionMetricsTableCompanion.insert(
              id: newId(),
              actionId: actionId,
              metricId: metricId,
            ),
          );
    });
  }

  /// Removes only the [actionId] - [metricId] link (the rows themselves stay).
  Future<void> unlinkAction(String actionId, String metricId) {
    return (db.delete(db.actionMetricsTable)..where(
          (t) => t.actionId.equals(actionId) & t.metricId.equals(metricId),
        ))
        .go();
  }

  Future<void> _insertEdge(String metricId, String dependsOnId) {
    return db
        .into(db.metricDependenciesTable)
        .insert(
          MetricDependenciesTableCompanion.insert(
            id: newId(),
            metricId: metricId,
            dependsOnId: dependsOnId,
          ),
        );
  }
}
