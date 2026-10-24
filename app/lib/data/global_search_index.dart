import '../domain/global_search.dart';
import 'database.dart';

/// Everything the Ctrl+K window can open, as light rows (id, title, a second
/// searchable line, the time of the last change). One query per kind; the change
/// time is the wall-clock part of the row's sync stamp (`sync_versions.hlc`), which
/// every synced table has - `metrics` and `action_templates` have no
/// `updated_at` column - falling back to `updated_at`. Rows that were never
/// changed since sync stamps began carry the epoch and count as "unknown".
Future<List<SearchHit>> loadSearchHits(AppDatabase db) async {
  DateTime? when(Object? v) {
    if (v == null) return null;
    final t = DateTime.tryParse(v.toString());
    if (t == null || t.year < 2000) return null;
    return t.toUtc();
  }

  Future<List<SearchHit>> run(
    SearchSection section,
    String sql, {
    String subtitleColumn = '',
  }) async {
    final rows = await db.customSelect(sql).get();
    return [
      for (final r in rows)
        SearchHit(
          section: section,
          id: r.read<String>('id'),
          title: r.read<String>('title'),
          subtitle: subtitleColumn.isEmpty
              ? ''
              : (r.readNullable<String>(subtitleColumn) ?? ''),
          icon: section == SearchSection.directions
              ? r.readNullable<String>('icon')
              : null,
          changedAt: when(r.readNullable<String>('changed')),
        ),
    ];
  }

  // `sync_versions` joins on (tbl, row_id); substr(hlc, 1, 24) is the wall time.
  String stamp(String table, String alias, {bool hasUpdatedAt = true}) =>
      hasUpdatedAt
      ? 'COALESCE(substr(sv.hlc, 1, 24), $alias.updated_at)'
      : 'substr(sv.hlc, 1, 24)';
  String join(String table, String alias) =>
      "LEFT JOIN sync_versions sv ON sv.tbl = '$table' AND sv.row_id = $alias.id";

  final lists = await Future.wait([
    run(
      SearchSection.actions,
      'SELECT a.id AS id, a.name AS title, ${stamp('actions', 'a')} AS changed '
      "FROM actions a ${join('actions', 'a')}",
    ),
    run(
      SearchSection.templates,
      'SELECT t.id AS id, t.name AS title, '
      "${stamp('action_templates', 't', hasUpdatedAt: false)} AS changed "
      "FROM action_templates t ${join('action_templates', 't')}",
    ),
    run(
      SearchSection.directions,
      'SELECT m.id AS id, m.name AS title, m.icon AS icon, '
      "${stamp('metrics', 'm', hasUpdatedAt: false)} AS changed "
      "FROM metrics m ${join('metrics', 'm')}",
    ),
    run(
      SearchSection.categories,
      'SELECT c.id AS id, c.name AS title, ${stamp('budget_categories', 'c')} '
      "AS changed FROM budget_categories c ${join('budget_categories', 'c')}",
    ),
    run(
      SearchSection.transactions,
      'SELECT t.id AS id, t.name AS title, '
      "TRIM(COALESCE(c.name, '') || ' ' || COALESCE(a.name, '')) AS sub, "
      "${stamp('budget_transactions', 't')} AS changed "
      'FROM budget_transactions t '
      'LEFT JOIN budget_categories c ON c.id = t.category_id '
      'LEFT JOIN actions a ON a.id = t.action_id '
      "${join('budget_transactions', 't')}",
      subtitleColumn: 'sub',
    ),
    run(
      SearchSection.forms,
      'SELECT f.id AS id, f.name AS title, ${stamp('forms', 'f')} AS changed '
      "FROM forms f ${join('forms', 'f')}",
    ),
    run(
      SearchSection.plans,
      'SELECT p.id AS id, p.name AS title, ${stamp('plan_items', 'p')} AS changed '
      "FROM plan_items p ${join('plan_items', 'p')}",
    ),
  ]);
  return [for (final l in lists) ...l];
}
