import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/data_exceptions.dart';
import '../core/error_log.dart';
import '../core/ids.dart';
import '../core/text_rules.dart';
import '../core/time_codec.dart';
import '../data/database.dart';
import 'action_service.dart';
import 'budget_service.dart';
import 'dependency_service.dart';
import 'duration_rules.dart' show defaultActionDuration;
import 'plan_rules.dart';

/// What the plan item editor saves.
class PlanItemInput {
  const PlanItemInput({
    this.id,
    required this.name,
    this.templateId,
    required this.kind,
    required this.startDate,
    this.endDate,
    this.forever = false,
    this.paused = false,
    this.cycle,
    this.monthly,
    this.manualMinutes,
    this.collectionIds = const [],
  });

  /// The plan collections the item belongs to.
  final List<String> collectionIds;

  final String? id;
  final String name;
  final String? templateId;
  final PlanKind kind;
  final DateTime startDate;
  final DateTime? endDate;
  final bool forever;
  final bool paused;
  final CycleRule? cycle;
  final MonthlyRule? monthly;

  /// The duration of a template created together with a NEW plan item (null =
  /// the default hour).
  final int? manualMinutes;
}

/// What a confirmation did: the actions it created (for ONE Undo) and how many
/// occurrences already had a real action.
class PlanConfirmResult {
  const PlanConfirmResult(
    this.createdIds,
    this.existing, {
    this.transactionIds = const [],
    this.skipped = 0,
  });

  /// Every action created: the main ones AND their Previous / Next companions.
  final List<String> createdIds;
  final int existing;

  /// The transactions created from transaction templates.
  final List<String> transactionIds;

  /// Links / transactions that could not be made (a cycle, a deleted template or
  /// category, a group category): counted, never fatal.
  final int skipped;
}

/// What bringing a deleted collection back takes: its row and the membership
/// (item id -> its collection ids before) of the items that were in it.
class PlanCollectionDeleteUndo {
  const PlanCollectionDeleteUndo(this.row, this.members);

  final PlanCollection row;
  final Map<String, List<String>> members;
}

/// Everything needed to bring a deleted plan item back.
class PlanDeleteUndo {
  const PlanDeleteUndo(this.item, this.overrides, this.removed);

  final PlanItem item;
  final List<PlanOverride> overrides;

  /// The future actions removed with it (null = none were removed).
  final DeleteManyUndo? removed;
}

/// Plan items, their per-day overrides and what they generate. The pure rules
/// are in `plan_rules.dart`; this class stores them and turns occurrences into
/// real actions (always through a template, so a plan and the Templates list
/// stay one catalogue).
int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

int _lcm(int a, int b) => a ~/ _gcd(a, b) * b;

class PlanService {
  PlanService(this.db, this.actions)
    : _budget = BudgetService(db),
      _deps = DependencyService(db);

  final AppDatabase db;
  final ActionService actions;
  final BudgetService _budget;
  final DependencyService _deps;

  // ---- reading ----------------------------------------------------------------

  /// A stored plan item as the generator reads it. A row whose dates are
  /// damaged does not throw (that would break every plan on the screen): a bad
  /// start date makes it PAUSED (it generates nothing) and is logged; a bad end
  /// date reads as "no end".
  PlanItemData decode(PlanItem r) {
    final kind = r.kind == 'monthly' ? PlanKind.monthly : PlanKind.cycle;
    final rule = PlanItemData.decodeRule(kind, r.rule);
    DateTime? date(String? key, String what) {
      if (key == null) return null;
      try {
        return planDateFromKey(key);
      } on Object catch (e, st) {
        unawaited(ErrorLog.write(e, st, context: 'plan $what "$key"'));
        return null;
      }
    }

    final start = date(r.startDate, 'start date');
    return PlanItemData(
      id: r.id,
      name: r.name,
      templateId: r.templateId,
      kind: kind,
      startDate: start ?? planDate(1970, 1, 1),
      endDate: date(r.endDate, 'end date'),
      forever: r.forever,
      paused: r.paused || start == null,
      cycle: rule.cycle,
      monthly: rule.monthly,
      collectionIds: decodeCollectionIds(r.collections),
    );
  }

  PlanOverrideData decodeOverride(PlanOverride o) => PlanOverrideData(
    date: planDateFromKey(o.date),
    index: o.occurrenceIndex,
    startMin: o.startMin,
    durationMin: o.durationMin,
    name: o.name,
    skipped: o.skipped,
  );

  Stream<List<PlanItem>> watchItems() =>
      (db.select(db.planItemsTable)..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .watch();

  Stream<List<PlanOverride>> watchOverrides() =>
      db.select(db.planOverridesTable).watch();

  Future<List<PlanItem>> items() => db.select(db.planItemsTable).get();

  // ---- writing ----------------------------------------------------------------

  Future<String> saveItem(PlanItemInput i) async {
    final clean = cleanName(i.name, what: 'plan name');
    if (clean.isEmpty) throw ArgumentError('A plan item needs a name.');
    final now = dateTimeToDb(DateTime.now())!;
    final rule = jsonEncode(
      i.kind == PlanKind.cycle ? i.cycle?.toJson() : i.monthly?.toJson(),
    );
    final id = i.id ?? newId();
    // A plan item made from scratch also becomes a template (name + duration), so
    // plans and the Templates list stay one catalogue.
    var templateId = i.templateId;
    if (templateId == null && i.id == null) {
      templateId = await _createTemplate(clean, i.manualMinutes);
    }
    final companion = PlanItemsTableCompanion(
      name: Value(clean),
      templateId: Value(templateId),
      kind: Value(i.kind.name),
      startDate: Value(planDateKey(i.startDate)),
      endDate: Value(i.endDate == null ? null : planDateKey(i.endDate!)),
      forever: Value(i.forever),
      paused: Value(i.paused),
      rule: Value(rule),
      collections: Value(
        i.collectionIds.isEmpty ? null : jsonEncode(i.collectionIds),
      ),
      updatedAt: Value(now),
    );
    if (i.id == null) {
      await db
          .into(db.planItemsTable)
          .insert(companion.copyWith(id: Value(id), createdAt: Value(now)));
    } else {
      final changed = await (db.update(db.planItemsTable)
            ..where((t) => t.id.equals(id)))
          .write(companion);
      if (changed == 0) {
        throw const MissingRowException('That plan no longer exists.');
      }
    }
    return id;
  }

  /// A new template (name, optional manual minutes) - the same payload the
  /// Templates editor writes.
  Future<String> _createTemplate(String name, int? minutes) async {
    final id = newId();
    await db
        .into(db.actionTemplatesTable)
        .insert(
          ActionTemplatesTableCompanion.insert(
            id: id,
            name: name,
            payload: jsonEncode({
              'name': name,
              'isAllDay': false,
              if (minutes != null && minutes > 0) 'estimatedMinutes': minutes,
              'metricIds': const <String>[],
            }),
          ),
        );
    return id;
  }

  // ---- collections -------------------------------------------------------------

  Stream<List<PlanCollection>> watchCollections() =>
      (db.select(db.planCollectionsTable)
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .watch();

  Future<List<PlanCollection>> collections() =>
      db.select(db.planCollectionsTable).get();

  /// Creates (no [id]) or renames a collection; returns its id.
  Future<String> saveCollection({String? id, required String name}) async {
    final clean = cleanName(name, what: 'collection name');
    if (clean.isEmpty) throw ArgumentError('A collection needs a name.');
    final now = dateTimeToDb(DateTime.now())!;
    if (id == null) {
      final nid = newId();
      await db
          .into(db.planCollectionsTable)
          .insert(
            PlanCollectionsTableCompanion.insert(
              id: nid,
              name: clean,
              createdAt: now,
              updatedAt: now,
            ),
          );
      return nid;
    }
    final changed = await (db.update(db.planCollectionsTable)
          ..where((t) => t.id.equals(id)))
        .write(
          PlanCollectionsTableCompanion(name: Value(clean), updatedAt: Value(now)),
        );
    if (changed == 0) {
      throw const MissingRowException('That collection no longer exists.');
    }
    return id;
  }

  Future<void> setCollectionVisible(String id, bool visible) =>
      (db.update(db.planCollectionsTable)..where((t) => t.id.equals(id))).write(
        PlanCollectionsTableCompanion(
          visible: Value(visible),
          updatedAt: Value(dateTimeToDb(DateTime.now())!),
        ),
      );

  /// Show all / hide all collections in one transaction (rows already in that
  /// state are not touched).
  Future<void> setAllCollectionsVisible(bool visible) =>
      db.transaction(() async {
        for (final c in await collections()) {
          if (c.visible != visible) await setCollectionVisible(c.id, visible);
        }
      });

  /// Replaces the collections of one plan item.
  Future<void> setItemCollections(String itemId, List<String> ids) =>
      (db.update(db.planItemsTable)..where((t) => t.id.equals(itemId))).write(
        PlanItemsTableCompanion(
          collections: Value(ids.isEmpty ? null : jsonEncode(ids)),
          updatedAt: Value(dateTimeToDb(DateTime.now())!),
        ),
      );

  /// Deletes a collection (its items stay; they just leave it). Returns what an
  /// Undo needs (null = it was already gone).
  Future<PlanCollectionDeleteUndo?> deleteCollection(String id) =>
      db.transaction(() async {
        final row = await (db.select(
          db.planCollectionsTable,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        if (row == null) return null;
        final before = <String, List<String>>{};
        for (final r in await items()) {
          final ids = decodeCollectionIds(r.collections);
          if (!ids.contains(id)) continue;
          before[r.id] = ids;
          await setItemCollections(r.id, [
            for (final c in ids)
              if (c != id) c,
          ]);
        }
        await (db.delete(
          db.planCollectionsTable,
        )..where((t) => t.id.equals(id))).go();
        return PlanCollectionDeleteUndo(row, before);
      });

  Future<void> undoDeleteCollection(PlanCollectionDeleteUndo u) =>
      db.transaction(() async {
        await db.into(db.planCollectionsTable).insertOnConflictUpdate(u.row);
        for (final e in u.members.entries) {
          await setItemCollections(e.key, e.value);
        }
      });

  /// "Whole pattern": the occurrence [index] of the plan item takes a new start
  /// time / duration in the RULE itself (every repetition changes), and its
  /// own "this day only" overrides are dropped.
  Future<void> shiftPattern(
    String itemId,
    int index, {
    required int startMin,
    required int durationMin,
  }) async {
    final row = await (db.select(
      db.planItemsTable,
    )..where((t) => t.id.equals(itemId))).getSingleOrNull();
    if (row == null) return;
    final data = decode(row);
    String rule;
    if (data.kind == PlanKind.cycle && data.cycle != null) {
      final occ = [...data.cycle!.occurrences];
      if (index < 0 || index >= occ.length) return;
      final o = occ[index];
      occ[index] = CycleOccurrence(
        day: o.day,
        startMin: startMin,
        durationMin: durationMin,
        name: o.name,
        templateId: o.templateId,
        extras: o.extras,
      );
      rule = jsonEncode(
        CycleRule(cycleDays: data.cycle!.cycleDays, occurrences: occ).toJson(),
      );
    } else if (data.monthly != null) {
      final m = data.monthly!;
      rule = jsonEncode(
        MonthlyRule(
          everyMonths: m.everyMonths,
          mode: m.mode,
          day: m.day,
          nth: m.nth,
          weekday: m.weekday,
          startMin: startMin,
          durationMin: durationMin,
          name: m.name,
          extras: m.extras,
        ).toJson(),
      );
    } else {
      return;
    }
    await (db.update(db.planItemsTable)..where((t) => t.id.equals(itemId)))
        .write(
          PlanItemsTableCompanion(
            rule: Value(rule),
            updatedAt: Value(dateTimeToDb(DateTime.now())!),
          ),
        );
    await (db.delete(db.planOverridesTable)
          ..where(
            (t) =>
                t.planItemId.equals(itemId) & t.occurrenceIndex.equals(index),
          ))
        .go();
  }

  /// "This weekday only": the occurrence [index] on [date] takes a new start time /
  /// duration in the RULE, but only on the weekdays of [date] - every other
  /// weekday of the pattern keeps its time.
  ///
  /// A cycle of N days is stretched to lcm(N, 7) days (a daily item becomes a
  /// weekly one with one row per weekday; a 3-day cycle becomes 21 days ...), the
  /// stretched row of that weekday is changed, and everything that is addressed
  /// by a row's position (this item's overrides and the `plan_key` of the actions
  /// it already made) is renumbered, so nothing is created twice later. A cycle
  /// that already is whole weeks, and a monthly rule, have nothing to split:
  /// that is [shiftPattern].
  Future<void> shiftWeekday(
    String itemId,
    DateTime date,
    int index, {
    required int startMin,
    required int durationMin,
  }) async {
    final row = await (db.select(
      db.planItemsTable,
    )..where((t) => t.id.equals(itemId))).getSingleOrNull();
    if (row == null) return;
    final data = decode(row);
    final rule = data.cycle;
    if (data.kind != PlanKind.cycle || rule == null) {
      return shiftPattern(itemId, index, startMin: startMin, durationMin: durationMin);
    }
    final n = rule.cycleDays < 1 ? 1 : rule.cycleDays;
    final l = _lcm(n, 7);
    final rep = l ~/ n;
    final c = rule.occurrences.length;
    if (rep == 1 || index < 0 || index >= c) {
      return shiftPattern(itemId, index, startMin: startMin, durationMin: durationMin);
    }

    int mod(int a, int m) => ((a % m) + m) % m;
    final oldStart = data.startDate;
    // The start date stays: a row's day always counts from it.

    final rows = <CycleOccurrence>[];
    for (var r = 0; r < rep; r++) {
      for (final o in rule.occurrences) {
        final day = (o.day % n) + r * n;
        rows.add(
          CycleOccurrence(
            day: day,
            startMin: o.startMin,
            durationMin: o.durationMin,
            name: o.name,
            templateId: o.templateId,
            extras: o.extras,
            allDay: o.allDay,
          ),
        );
      }
    }

    int newIndex(DateTime d, int oldIndex) {
      final p = mod(d.difference(oldStart).inDays, l);
      return oldIndex + (p ~/ n) * c;
    }

    final target = newIndex(date, index);
    final o = rows[target];
    rows[target] = CycleOccurrence(
      day: o.day,
      startMin: startMin,
      durationMin: durationMin,
      name: o.name,
      templateId: o.templateId,
      extras: o.extras,
      allDay: o.allDay,
    );

    final now = dateTimeToDb(DateTime.now())!;
    await db.transaction(() async {
      await (db.update(db.planItemsTable)..where((t) => t.id.equals(itemId)))
          .write(
            PlanItemsTableCompanion(
              rule: Value(
                jsonEncode(CycleRule(cycleDays: l, occurrences: rows).toJson()),
              ),
              updatedAt: Value(now),
            ),
          );
      // Overrides are keyed by row position: renumber them.
      for (final ov in await (db.select(
        db.planOverridesTable,
      )..where((t) => t.planItemId.equals(itemId))).get()) {
        final d = planDateFromKey(ov.date);
        final ni = newIndex(d, ov.occurrenceIndex);
        if (ni == ov.occurrenceIndex) continue;
        await (db.delete(
          db.planOverridesTable,
        )..where((t) => t.id.equals(ov.id))).go();
        await db
            .into(db.planOverridesTable)
            .insert(
              PlanOverridesTableCompanion.insert(
                id: overrideId(itemId, d, ni),
                planItemId: itemId,
                date: ov.date,
                occurrenceIndex: Value(ni),
                startMin: Value(ov.startMin),
                durationMin: Value(ov.durationMin),
                name: Value(ov.name),
                skipped: Value(ov.skipped),
                createdAt: ov.createdAt,
                updatedAt: now,
              ),
            );
      }
      // The row of this weekday was just changed for ALL its dates: its old
      // single-day edits no longer apply.
      await (db.delete(db.planOverridesTable)..where(
            (t) => t.planItemId.equals(itemId) & t.occurrenceIndex.equals(target),
          ))
          .go();
      // The actions already made keep their place in the pattern: renumber the
      // row part of their plan_key (`YYYY-MM-DD#row` and `...>p0` / `>n0`).
      final re = RegExp(r'^(\d{4}-\d{2}-\d{2})#(\d+)(.*)$');
      for (final a in await (db.select(db.actionsTable)..where(
            (t) => t.planItemId.equals(itemId) & t.planKey.isNotNull(),
          ))
          .get()) {
        final m = re.firstMatch(a.planKey!);
        if (m == null) continue;
        final oldRow = int.parse(m.group(2)!);
        final ni = newIndex(planDateFromKey(m.group(1)!), oldRow);
        if (ni == oldRow) continue;
        await (db.update(db.actionsTable)..where((t) => t.id.equals(a.id))).write(
          ActionsTableCompanion(planKey: Value('${m.group(1)}#$ni${m.group(3)}')),
        );
      }
    });
  }

  Future<void> setPaused(String id, bool paused) =>
      (db.update(db.planItemsTable)..where((t) => t.id.equals(id))).write(
        PlanItemsTableCompanion(
          paused: Value(paused),
          updatedAt: Value(dateTimeToDb(DateTime.now())!),
        ),
      );

  Future<void> setForever(String id, bool forever) =>
      (db.update(db.planItemsTable)..where((t) => t.id.equals(id))).write(
        PlanItemsTableCompanion(
          forever: Value(forever),
          updatedAt: Value(dateTimeToDb(DateTime.now())!),
        ),
      );

  /// Deletes a plan item (its overrides go with it). With [removeFuture] the
  /// still-untouched future actions it generated are deleted too.
  Future<PlanDeleteUndo?> deleteItem(
    String id, {
    bool removeFuture = false,
  }) {
    // One transaction: a failure halfway must not leave overrides deleted
    // under a plan item that is still there (or future actions removed).
    return db.transaction(() async {
      final item = await (db.select(
        db.planItemsTable,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (item == null) return null;
      final overrides = await (db.select(
        db.planOverridesTable,
      )..where((t) => t.planItemId.equals(id))).get();
      DeleteManyUndo? removed;
      if (removeFuture) removed = await this.removeFuture(id);
      await (db.delete(db.planOverridesTable)
            ..where((t) => t.planItemId.equals(id)))
          .go();
      await (db.delete(db.planItemsTable)..where((t) => t.id.equals(id))).go();
      return PlanDeleteUndo(item, overrides, removed);
    });
  }

  Future<void> undoDeleteItem(PlanDeleteUndo u) {
    return db.transaction(() async {
      await db.into(db.planItemsTable).insertOnConflictUpdate(u.item);
      for (final o in u.overrides) {
        await db.into(db.planOverridesTable).insertOnConflictUpdate(o);
      }
      if (u.removed != null) await actions.undoDeleteMany(u.removed!);
    });
  }

  String overrideId(String itemId, DateTime date, int index) =>
      '$itemId|${planDateKey(date)}|$index';

  /// "This day only": the occurrence on [date] (index [index] of its item) is
  /// moved / renamed / given another duration, or [skipped].
  Future<void> setOverride({
    required String itemId,
    required DateTime date,
    required int index,
    int? startMin,
    int? durationMin,
    String? name,
    bool skipped = false,
  }) async {
    final now = dateTimeToDb(DateTime.now())!;
    await db
        .into(db.planOverridesTable)
        .insertOnConflictUpdate(
          PlanOverridesTableCompanion.insert(
            id: overrideId(itemId, date, index),
            planItemId: itemId,
            date: planDateKey(date),
            occurrenceIndex: Value(index),
            startMin: Value(startMin),
            durationMin: Value(durationMin),
            name: Value(name),
            skipped: Value(skipped),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<void> clearOverride(String itemId, DateTime date, int index) =>
      (db.delete(db.planOverridesTable)
            ..where((t) => t.id.equals(overrideId(itemId, date, index))))
          .go();

  /// "Skip this day": hides the occurrence on [date] (index [index] of its
  /// item) without touching the rule. Returns what was stored for that day
  /// before (null = nothing) so [undoSkip] can put it back exactly.
  Future<PlanOverride?> skipOccurrence(
    String itemId,
    DateTime date,
    int index,
  ) async {
    final id = overrideId(itemId, date, index);
    final before = await (db.select(
      db.planOverridesTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    await setOverride(
      itemId: itemId,
      date: date,
      index: index,
      skipped: true,
    );
    return before;
  }

  Future<void> undoSkip(
    String itemId,
    DateTime date,
    int index,
    PlanOverride? before,
  ) async {
    if (before == null) {
      await clearOverride(itemId, date, index);
    } else {
      await db.into(db.planOverridesTable).insertOnConflictUpdate(before);
    }
  }

  // ---- generating -------------------------------------------------------------

  /// The duration an occurrence of [item] gets when it has none of its own: its
  /// template's (manual minutes or the average of finished runs), else 60.
  Future<int> defaultMinutes(PlanItemData item) async {
    final t = item.templateId;
    if (t == null) return defaultActionDuration.inMinutes;
    final d = await actions.templateDuration(t);
    return (d ?? defaultActionDuration).inMinutes;
  }

  /// Every occurrence of the (unpaused) plan items on [from]..[to] (local
  /// dates), overrides applied, ordered by start. [itemIds] narrows it.
  Future<List<PlanOccurrence>> occurrences(
    DateTime from,
    DateTime to, {
    Set<String>? itemIds,
  }) async {
    final rows = [
      for (final r in await items())
        if (itemIds == null || itemIds.contains(r.id)) r,
    ];
    if (rows.isEmpty) return const [];
    final overrides = <String, List<PlanOverrideData>>{};
    for (final o in await db.select(db.planOverridesTable).get()) {
      overrides.putIfAbsent(o.planItemId, () => []).add(decodeOverride(o));
    }
    final out = <PlanOccurrence>[];
    for (final r in rows) {
      final data = decode(r);
      if (data.paused) continue;
      out.addAll(
        occurrencesInRange(
          data,
          from,
          to,
          overrides: overrides[r.id] ?? const [],
          defaultMinutes: await defaultMinutes(data),
        ),
      );
    }
    out.sort((a, b) => a.startUtc.compareTo(b.startUtc));
    return out;
  }

  // ---- confirming -------------------------------------------------------------

  /// What a confirmation WOULD do: the occurrences that start after now and have
  /// no real action yet ([toCreate]) and how many already do ([existing]).
  Future<({List<PlanOccurrence> toCreate, int existing})> preview({
    Set<String>? itemIds,
    required DateTime from,
    required DateTime to,
    DateTime? nowUtc,
  }) async {
    final now = (nowUtc ?? DateTime.now()).toUtc();
    final occs = await occurrences(from, to, itemIds: itemIds);
    // An all-day occurrence counts from the start of its day: today's still is.
    final today = planDateOf(now);
    final future = [
      for (final o in occs)
        if (o.startUtc.isAfter(now) || (o.allDay && !o.date.isBefore(today))) o,
    ];
    if (future.isEmpty) return (toCreate: const <PlanOccurrence>[], existing: 0);
    final ids = {for (final o in future) o.planItemId};
    final existingKeys = <String>{};
    for (final a in await (db.select(db.actionsTable)
          ..where((t) => t.planItemId.isIn(ids) & t.planKey.isNotNull()))
        .get()) {
      existingKeys.add('${a.planItemId}|${a.planKey}');
    }
    final fresh = <PlanOccurrence>[];
    var existing = 0;
    for (final o in future) {
      if (existingKeys.contains('${o.planItemId}|${o.key}')) {
        existing++;
      } else {
        fresh.add(o);
      }
    }
    return (toCreate: fresh, existing: existing);
  }

  /// Turns the plan into REAL actions for the local dates [from]..[to]: every
  /// occurrence that starts after now and has no real action yet (same plan item
  /// and key) becomes an action - through its template when it has one - in ONE
  /// transaction. The plan item keeps its settings; the actions are ordinary.
  Future<PlanConfirmResult> confirm({
    Set<String>? itemIds,
    required DateTime from,
    required DateTime to,
    DateTime? nowUtc,
  }) async {
    final p = await preview(itemIds: itemIds, from: from, to: to, nowUtc: nowUtc);
    if (p.toCreate.isEmpty) return PlanConfirmResult(const [], p.existing);
    final templates = <String, bool>{};
    Future<bool> templateExists(String id) async =>
        templates[id] ??= await (db.select(
              db.actionTemplatesTable,
            )..where((t) => t.id.equals(id))).getSingleOrNull() !=
            null;

    final created = <String>[];
    final transactionIds = <String>[];
    var skipped = 0;

    // A Previous / Next companion: through its template when it has one, else a
    // plain action; keyed `<occurrence key>>p<n>` / `>n<n>`.
    Future<String> createCompanion(
      PlanOccurrence o,
      PlanCompanion c,
      DateTime start,
      DateTime end,
      String key,
      String fallbackName,
    ) async {
      final tid = c.templateId;
      if (tid != null && await templateExists(tid)) {
        return actions.createFromTemplateAt(
          tid,
          start,
          duration: end.difference(start),
          name: c.name,
          planItemId: o.planItemId,
          planKey: key,
        );
      }
      return actions.createAction(
        name: c.name ?? fallbackName,
        startAt: start,
        endAt: end,
        planItemId: o.planItemId,
        planKey: key,
      );
    }

    Future<void> makeTransactions(
      List<String> templateIds,
      String actionId,
      DateTime date,
      String name,
    ) async {
      for (final t in templateIds) {
        try {
          transactionIds.add(
            await _budget.createTransactionFromTemplate(
              t,
              actionId: actionId,
              date: date,
              fallbackName: name,
            ),
          );
        } on BudgetGroupException {
          skipped++;
        } on StateError {
          skipped++;
        }
      }
    }

    Future<void> link(String predecessor, String successor) async {
      try {
        await _deps.addDependency(
          predecessorId: predecessor,
          successorId: successor,
        );
      } on DependencyCycleException {
        skipped++;
      }
    }

    await db.transaction(() async {
      for (final o in p.toCreate) {
        final tid = o.templateId;
        final String id;
        if (tid != null && await templateExists(tid)) {
          id = await actions.createFromTemplateAt(
            tid,
            o.startUtc,
            duration: o.endUtc.difference(o.startUtc),
            // An occurrence with a name of its own keeps it; otherwise the
            // action is called what its template is called.
            name: o.ownName ? o.name : null,
            planItemId: o.planItemId,
            planKey: o.key,
            allDay: o.allDay ? true : null,
          );
        } else {
          id = await actions.createAction(
            name: o.name,
            startAt: o.startUtc,
            endAt: o.allDay ? null : o.endUtc,
            isAllDay: o.allDay,
            planItemId: o.planItemId,
            planKey: o.key,
          );
        }
        created.add(id);
        await makeTransactions(o.extras.txTemplateIds, id, o.startUtc, o.name);
        // An all-day row has no time to put a Previous / Next action next to.
        if (o.allDay) continue;
        for (var n = 0; n < o.extras.prev.length; n++) {
          final c = o.extras.prev[n];
          final end = o.startUtc.subtract(Duration(minutes: c.gapMinutes));
          final start = end.subtract(Duration(minutes: c.minutes));
          final cid = await createCompanion(
            o,
            c,
            start,
            end,
            '${o.key}>p$n',
            '${o.name} - before',
          );
          created.add(cid);
          await link(cid, id);
          await makeTransactions(c.txTemplateIds, cid, start, c.name ?? o.name);
        }
        for (var n = 0; n < o.extras.next.length; n++) {
          final c = o.extras.next[n];
          final start = o.endUtc.add(Duration(minutes: c.gapMinutes));
          final end = start.add(Duration(minutes: c.minutes));
          final cid = await createCompanion(
            o,
            c,
            start,
            end,
            '${o.key}>n$n',
            '${o.name} - after',
          );
          created.add(cid);
          await link(id, cid);
          await makeTransactions(c.txTemplateIds, cid, start, c.name ?? o.name);
        }
      }
    });
    return PlanConfirmResult(
      created,
      p.existing,
      transactionIds: transactionIds,
      skipped: skipped,
    );
  }

  /// Takes back a confirmation (the actions were just created: no history). The
  /// transactions go FIRST: deleting an action would only detach them.
  Future<DeleteManyUndo> undoConfirm(
    List<String> ids, {
    List<String> transactionIds = const [],
  }) async {
    if (transactionIds.isNotEmpty) {
      await (db.delete(
        db.budgetTransactionsTable,
      )..where((t) => t.id.isIn(transactionIds))).go();
    }
    return actions.deleteActions(ids);
  }

  /// Deletes the plan item's generated actions that are still in the future, not
  /// done and never edited since they were created. Returns the undo (null when
  /// there was nothing to remove).
  Future<DeleteManyUndo?> removeFuture(String itemId, {DateTime? nowUtc}) async {
    final now = (nowUtc ?? DateTime.now()).toUtc();
    final nowText = dateTimeToDb(now)!;
    // An all-day action counts from the start of its day (today's still is).
    final todayText = dateTimeToDb(planInstant(planDateOf(now), 0))!;
    final rows = await (db.select(db.actionsTable)
          ..where(
            (t) =>
                t.planItemId.equals(itemId) &
                t.done.equals(false) &
                (t.startAt.isBiggerThanValue(nowText) |
                    (t.isAllDay.equals(true) &
                        t.startAt.isBiggerOrEqualValue(todayText))) &
                t.updatedAt.equalsExp(t.createdAt),
          ))
        .get();
    if (rows.isEmpty) return null;
    return actions.deleteActions([for (final r in rows) r.id]);
  }

  /// The "forever" items keep a rolling window of real actions: [weeks] ahead
  /// from today. Run when the app opens (and again each day).
  Future<PlanConfirmResult> refillForever({int weeks = 8, DateTime? nowUtc}) async {
    final now = (nowUtc ?? DateTime.now()).toUtc();
    final forever = {
      for (final r in await items())
        if (r.forever && !r.paused) r.id,
    };
    if (forever.isEmpty) return const PlanConfirmResult([], 0);
    final today = planDateOf(now);
    return confirm(
      itemIds: forever,
      from: today,
      to: DateTime.utc(today.year, today.month, today.day + weeks * 7),
      nowUtc: now,
    );
  }
}
