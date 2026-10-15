import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/ids.dart';
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
  });

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
class PlanService {
  PlanService(this.db, this.actions)
    : _budget = BudgetService(db),
      _deps = DependencyService(db);

  final AppDatabase db;
  final ActionService actions;
  final BudgetService _budget;
  final DependencyService _deps;

  // ---- reading ----------------------------------------------------------------

  PlanItemData decode(PlanItem r) {
    final kind = r.kind == 'monthly' ? PlanKind.monthly : PlanKind.cycle;
    final rule = PlanItemData.decodeRule(kind, r.rule);
    return PlanItemData(
      id: r.id,
      name: r.name,
      templateId: r.templateId,
      kind: kind,
      startDate: planDateFromKey(r.startDate),
      endDate: r.endDate == null ? null : planDateFromKey(r.endDate!),
      forever: r.forever,
      paused: r.paused,
      cycle: rule.cycle,
      monthly: rule.monthly,
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
    final clean = i.name.trim();
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
      updatedAt: Value(now),
    );
    if (i.id == null) {
      await db
          .into(db.planItemsTable)
          .insert(companion.copyWith(id: Value(id), createdAt: Value(now)));
    } else {
      await (db.update(db.planItemsTable)..where((t) => t.id.equals(id)))
          .write(companion);
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
  }) async {
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
  }

  Future<void> undoDeleteItem(PlanDeleteUndo u) async {
    await db.into(db.planItemsTable).insertOnConflictUpdate(u.item);
    for (final o in u.overrides) {
      await db.into(db.planOverridesTable).insertOnConflictUpdate(o);
    }
    if (u.removed != null) await actions.undoDeleteMany(u.removed!);
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
    final future = [
      for (final o in occs)
        if (o.startUtc.isAfter(now)) o,
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
          );
        } else {
          id = await actions.createAction(
            name: o.name,
            startAt: o.startUtc,
            endAt: o.endUtc,
            planItemId: o.planItemId,
            planKey: o.key,
          );
        }
        created.add(id);
        await makeTransactions(o.extras.txTemplateIds, id, o.startUtc, o.name);
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
    final nowText = dateTimeToDb(nowUtc ?? DateTime.now())!;
    final rows = await (db.select(db.actionsTable)
          ..where(
            (t) =>
                t.planItemId.equals(itemId) &
                t.done.equals(false) &
                t.startAt.isBiggerThanValue(nowText) &
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
