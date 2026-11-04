import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/ids.dart';
import 'package:livenow/core/time_codec.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/providers.dart';

/// Counts the batched average reads (one per recomputation).
class _CountingService extends ActionService {
  _CountingService(super.db);
  int reads = 0;

  @override
  Future<Map<String, Duration>> averagesByName(
    Iterable<String> names, {
    DateTime? nowUtc,
  }) {
    reads++;
    return super.averagesByName(names, nowUtc: nowUtc);
  }
}

void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late _CountingService service;
  late ProviderContainer container;

  Future<String> template(String name) async {
    final id = newId();
    await db.into(db.actionTemplatesTable).insert(
      ActionTemplatesTableCompanion.insert(
        id: id,
        name: name,
        payload: jsonEncode({'name': name}),
      ),
    );
    return id;
  }

  Future<void> finishedRun(String name, int minutes) async {
    final end = DateTime.now().toUtc().subtract(const Duration(days: 1));
    final start = end.subtract(Duration(minutes: minutes));
    await db.into(db.actionsTable).insert(
      ActionsTableCompanion.insert(
        id: newId(),
        name: name,
        createdAt: dateTimeToDb(start)!,
        updatedAt: dateTimeToDb(DateTime.now().toUtc())!,
        done: const Value(true),
        startAt: Value(dateTimeToDb(start)),
        endAt: Value(dateTimeToDb(end)),
        completedAt: Value(dateTimeToDb(end)),
      ),
    );
  }

  Future<void> quiet() => Future<void>.delayed(const Duration(milliseconds: 1500));

  Future<Map<String, Duration>> averages() async =>
      container.read(templateAveragesProvider.future);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = _CountingService(db);
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        actionServiceProvider.overrideWithValue(service),
      ],
    );
    // The screen keeps the providers alive.
    container.listen(templatesProvider, (_, _) {});
    container.listen(templateAveragesProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('averages of all templates come from ONE batched read', () async {
    final read = await template('Read');
    final run = await template('Run');
    await template('Nothing');
    await finishedRun('Read', 30);
    await finishedRun('Read', 50);
    await finishedRun('Run', 20);
    container.read(templatesTabVisibleProvider.notifier).state = true;
    await container.read(templatesProvider.future);
    final m = await averages();
    expect(m, {read: const Duration(minutes: 40), run: const Duration(minutes: 20)});
    expect(service.reads, 1, reason: 'one pass for three templates');
  });

  test('an unrelated action write does not recompute; a finished run does', () async {
    final read = await template('Read');
    await finishedRun('Read', 30);
    container.read(templatesTabVisibleProvider.notifier).state = true;
    await container.read(templatesProvider.future);
    await averages();
    await quiet();
    final before = service.reads;

    // An open action (not finished): nothing to recompute.
    await db.into(db.actionsTable).insert(
      ActionsTableCompanion.insert(
        id: newId(),
        name: 'Something open',
        createdAt: dateTimeToDb(DateTime.now().toUtc())!,
        updatedAt: dateTimeToDb(DateTime.now().toUtc())!,
      ),
    );
    await quiet();
    expect(service.reads, before);

    await finishedRun('Read', 90);
    await quiet();
    expect(service.reads, before + 1);
    expect((await averages())[read], const Duration(minutes: 60));
  });

  test('a hidden tab keeps its values and recomputes only when shown again', () async {
    final read = await template('Read');
    await finishedRun('Read', 30);
    final visible = container.read(templatesTabVisibleProvider.notifier);
    visible.state = true;
    await container.read(templatesProvider.future);
    await averages();
    await quiet();
    final before = service.reads;

    visible.state = false;
    await finishedRun('Read', 90);
    await quiet();
    expect(service.reads, before, reason: 'hidden: nothing is computed');
    expect((await averages())[read], const Duration(minutes: 30), reason: 'the last value stays');

    visible.state = true;
    await quiet();
    expect(service.reads, before + 1);
    expect((await averages())[read], const Duration(minutes: 60));

    // Hidden and shown again with nothing changed: no work.
    visible.state = false;
    await quiet();
    visible.state = true;
    await quiet();
    expect(service.reads, before + 1);
  });
}
