import 'package:drift/drift.dart' show Variable;

import '../../data/database.dart';
import '../action_service.dart';

/// T4: a shop/bazaar action around a receipt that has none, with the growth
/// directions and countable activity of the most recent action of that name.
class ActionCreator {
  ActionCreator(this.db, this.actions);

  final AppDatabase db;
  final ActionService actions;

  /// Creates [name] spanning [receiptUtc] +/- [minutes] (default 20) and
  /// returns its id. [id] (e.g. `deriveId(jobId, 'action')`) makes a re-run
  /// return the same action. Links are copied from the newest same-name action
  /// (by `start_at`), if any.
  Future<String> create({
    required String name,
    required DateTime receiptUtc,
    int minutes = 20,
    String? id,
  }) async {
    final latest = await db
        .customSelect(
          'SELECT id, countable_activity_id AS c FROM actions WHERE name = ? '
          'ORDER BY start_at IS NULL, start_at DESC LIMIT 1',
          variables: [Variable.withString(name)],
        )
        .getSingleOrNull();
    var metricIds = <String>[];
    String? countableId;
    if (latest != null) {
      countableId = latest.read<String?>('c');
      final links = await db
          .customSelect(
            'SELECT metric_id FROM action_metrics WHERE action_id = ?',
            variables: [Variable.withString(latest.read<String>('id'))],
          )
          .get();
      metricIds = [for (final l in links) l.read<String>('metric_id')];
    }
    final half = Duration(minutes: minutes);
    return actions.createAction(
      id: id,
      name: name,
      startAt: receiptUtc.subtract(half),
      endAt: receiptUtc.add(half),
      countableActivityId: countableId,
      metricIds: metricIds,
    );
  }
}
