import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/time_codec.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/widgets/action_editor.dart';
import 'package:livenow/ui/widgets/date_time_field.dart';

/// The editor's quick buttons work from the times shown in the form, not from
/// the older saved ones: change Start (or End) without saving, press a button,
/// and the change is kept (it used to jump back to the saved Start).
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late String id;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  DateTime minute(DateTime t) =>
      DateTime.utc(t.year, t.month, t.day, t.hour, t.minute);

  Future<void> open(WidgetTester tester, DateTime start, DateTime end) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    late ActionRow row;
    await tester.runAsync(() async {
      final c = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      id = await c
          .read(actionServiceProvider)
          .createAction(name: 'Тест', startAt: start, endAt: end);
      row = await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(id))).getSingle();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => ActionEditorDialog.show(context, existing: row),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    resetStackedDialogsForTest();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Finder field(String label) =>
      find.byWidgetPredicate((w) => w is DateTimeField && w.label == label);
  DateTime? shown(WidgetTester tester, String label) =>
      tester.widget<DateTimeField>(field(label)).value;

  Future<ActionRow> saved(WidgetTester tester) async =>
      (await tester.runAsync(
        () => (db.select(db.actionsTable)..where((t) => t.id.equals(id))).getSingle(),
      ))!;

  testWidgets('Start typed in the form survives Finish', (tester) async {
    final now = DateTime.now().toUtc();
    final saved0 = minute(now.subtract(const Duration(minutes: 2)));
    await open(tester, saved0, saved0); // 14:48-14:48 style: zero length
    final typed = minute(now.subtract(const Duration(minutes: 10)));

    // The user types a new Start (the form moves the End along), does NOT save.
    tester.widget<DateTimeField>(field('Start')).onChanged(typed);
    await tester.pump();
    expect(shown(tester, 'Start'), typed);

    await tester.tap(find.byTooltip('Finish'));
    await settle(tester);

    final row = await saved(tester);
    expect(dateTimeFromDb(row.startAt), typed);
    expect(
      dateTimeFromDb(row.endAt)!.difference(DateTime.now().toUtc()).abs(),
      lessThan(const Duration(seconds: 20)),
    );
    expect(row.done, isTrue);
    // The form shows what was saved: the typed Start, not the old one.
    expect(shown(tester, 'Start'), typed);
    await unmount(tester);
  });

  testWidgets('an End typed in the form is the base of Prolong 30 min', (
    tester,
  ) async {
    final start = minute(DateTime.now().toUtc().add(const Duration(hours: 1)));
    await open(tester, start, start.add(const Duration(hours: 1)));
    final typedEnd = start.add(const Duration(hours: 3));
    tester.widget<DateTimeField>(field('End')).onChanged(typedEnd);
    await tester.pump();

    await tester.tap(find.byTooltip('Prolong 30 min'));
    await settle(tester);

    final row = await saved(tester);
    expect(dateTimeFromDb(row.startAt), start);
    expect(
      dateTimeFromDb(row.endAt),
      typedEnd.add(const Duration(minutes: 30)),
    );
    await unmount(tester);
  });

  testWidgets('without edits a button works from the saved times', (tester) async {
    final start = minute(DateTime.now().toUtc().add(const Duration(hours: 1)));
    final end = start.add(const Duration(hours: 1));
    await open(tester, start, end);
    await tester.tap(find.byTooltip('Prolong 30 min'));
    await settle(tester);
    final row = await saved(tester);
    expect(dateTimeFromDb(row.startAt), start);
    expect(dateTimeFromDb(row.endAt), end.add(const Duration(minutes: 30)));
    await unmount(tester);
  });
}
