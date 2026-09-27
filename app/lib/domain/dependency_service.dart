import 'package:drift/drift.dart';

import '../core/ids.dart';
import '../data/database.dart';

/// Thrown by [DependencyService.addDependency] when the requested edge would
/// create a cycle in the previous/next action chain.
class DependencyCycleException implements Exception {
  final String predecessorId;
  final String successorId;

  DependencyCycleException({
    required this.predecessorId,
    required this.successorId,
  });

  @override
  String toString() =>
      'Adding $predecessorId -> $successorId would create a dependency cycle.';
}

/// Manages the previous/next action chain (`action_dependencies`) — the
/// core GTD dependency feature. There is no parent/child hierarchy here.
class DependencyService {
  final AppDatabase db;

  DependencyService(this.db);

  /// Links [predecessorId] -> [successorId] ("this must follow that").
  /// Rejects self-links and anything that would create a cycle. Adding a
  /// duplicate edge is a no-op.
  Future<void> addDependency({
    required String predecessorId,
    required String successorId,
  }) async {
    if (predecessorId == successorId) {
      throw ArgumentError('An action cannot depend on itself.');
    }
    if (await _isReachable(from: successorId, to: predecessorId)) {
      throw DependencyCycleException(
        predecessorId: predecessorId,
        successorId: successorId,
      );
    }
    await db
        .into(db.actionDependenciesTable)
        .insert(
          ActionDependenciesTableCompanion.insert(
            id: newId(),
            predecessorId: predecessorId,
            successorId: successorId,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> removeDependency({
    required String predecessorId,
    required String successorId,
  }) {
    return (db.delete(db.actionDependenciesTable)..where(
          (t) =>
              t.predecessorId.equals(predecessorId) &
              t.successorId.equals(successorId),
        ))
        .go();
  }

  /// Whether [to] can be reached by following successor edges forward from
  /// [from] — i.e. whether [from] already "leads to" [to] somewhere down the
  /// chain. Used to reject an edge that would close a loop.
  Future<bool> _isReachable({
    required String from,
    required String to,
  }) async {
    final row = await db
        .customSelect(
          '''
          WITH RECURSIVE downstream(id) AS (
            SELECT successor_id FROM action_dependencies WHERE predecessor_id = ?
            UNION
            SELECT d.successor_id FROM action_dependencies d
            JOIN downstream ON d.predecessor_id = downstream.id
          )
          SELECT EXISTS(SELECT 1 FROM downstream WHERE id = ?) AS found
          ''',
          variables: [Variable.withString(from), Variable.withString(to)],
          readsFrom: {db.actionDependenciesTable},
        )
        .getSingle();
    return row.read<bool>('found');
  }
}
