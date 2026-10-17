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
import 'package:livenow/ui/widgets/quick_time_edit_dialog.dart';

/// A NEW action opens with Start = now and End = now + 60 min, the same button
/// row as when editing (acting on the form only) and the date/time edit menu.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(1400, 1200),
    DateTime? initialStart,
    DateTime? initialEnd,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => ActionEditorDialog.show(
                  context,
                  initialStart: initialStart,
                  initialEnd: initialEnd,
                ),
                child: const Text('open'),
              ),
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

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is DateTimeField && w.label == label,
  );
  DateTime? value(WidgetTester tester, String label) =>
      tester.widget<DateTimeField>(field(label)).value;
  Future<void> tapButton(WidgetTester tester, String tooltip) async {
    await tester.tap(find.byTooltip(tooltip));
    await tester.pump();
  }

  testWidgets('a new action opens with Start now (to the minute) and End 60 minutes later', (
    tester,
  ) async {
    final before = DateTime.now().toUtc();
    await open(tester);
    final after = DateTime.now().toUtc();

    final start = value(tester, 'Start')!;
    final end = value(tester, 'End')!;
    expect(end.difference(start), const Duration(minutes: 60));
    expect(start.second, 0);
    // Now, to the minute: not before the minute the dialog was opened in.
    final floor = DateTime.utc(
      before.year,
      before.month,
      before.day,
      before.hour,
      before.minute,
    );
    expect(start.isBefore(floor), isFalse);
    expect(start.isAfter(after), isFalse);
    expect(find.text('Duration: 1 hour'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the button row is there; Continue and Delete are not', (tester) async {
    await open(tester);
    for (final tip in [
      'Start',
      'Finish',
      'Prolong 30 min',
      'Postpone +1 hour',
      'Postpone +5 hours',
      'Postpone: tomorrow morning',
      'Postpone: next working morning',
      'Postpone: next week',
      'Postpone: next Monday morning',
    ]) {
      expect(find.byTooltip(tip), findsOneWidget, reason: tip);
    }
    expect(find.byTooltip('Continue with same action'), findsNothing);
    expect(find.byTooltip('Delete'), findsNothing);
    await unmount(tester);
  });

  testWidgets('Postpone +1 hour moves Start and End by an hour in the form only', (
    tester,
  ) async {
    await open(tester);
    final start = value(tester, 'Start')!;
    final end = value(tester, 'End')!;

    await tapButton(tester, 'Postpone +1 hour');

    expect(value(tester, 'Start'), start.add(const Duration(hours: 1)));
    expect(value(tester, 'End'), end.add(const Duration(hours: 1)));
    expect(await tester.runAsync(() => db.select(db.actionsTable).get()), isEmpty);
    await unmount(tester);
  });

  testWidgets('Prolong 30 min lengthens it', (tester) async {
    await open(tester);
    final start = value(tester, 'Start')!;
    final end = value(tester, 'End')!;
    await tapButton(tester, 'Prolong 30 min');
    expect(value(tester, 'Start'), start);
    expect(value(tester, 'End'), end.add(const Duration(minutes: 30)));
    expect(find.text('Duration: 1 hour 30 min'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('Start brings a postponed form back to now, keeping the length', (
    tester,
  ) async {
    await open(tester);
    await tapButton(tester, 'Postpone +5 hours');
    final before = DateTime.now().toUtc();
    await tapButton(tester, 'Start');
    final start = value(tester, 'Start')!;
    expect(start.difference(before).inSeconds.abs(), lessThan(5));
    expect(
      value(tester, 'End')!.difference(start),
      const Duration(minutes: 60),
    );
    await unmount(tester);
  });

  testWidgets('Finish ends now and puts the start an hour before when it was ahead', (
    tester,
  ) async {
    await open(tester);
    await tapButton(tester, 'Postpone +5 hours');
    final before = DateTime.now().toUtc();
    await tapButton(tester, 'Finish');
    final end = value(tester, 'End')!;
    expect(end.difference(before).inSeconds.abs(), lessThan(5));
    expect(end.difference(value(tester, 'Start')!), const Duration(minutes: 60));
    await unmount(tester);
  });

  testWidgets('Save creates the action with the form\'s times, Cancel creates nothing', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(find.byType(TextFormField).first, 'Call mum');
    await tapButton(tester, 'Postpone +1 hour');
    final start = value(tester, 'Start')!;
    final end = value(tester, 'End')!;

    await tester.tap(find.text('Save'));
    await settle(tester);

    final rows = (await tester.runAsync(() => db.select(db.actionsTable).get()))!;
    expect(rows, hasLength(1));
    expect(rows.single.name, 'Call mum');
    // (Compared as instants: a TZDateTime never equals a plain DateTime.)
    expect(
      dateTimeFromDb(rows.single.startAt)!.millisecondsSinceEpoch,
      start.millisecondsSinceEpoch,
    );
    expect(
      dateTimeFromDb(rows.single.endAt)!.millisecondsSinceEpoch,
      end.millisecondsSinceEpoch,
    );
    expect(rows.single.isAllDay, isFalse);
    await unmount(tester);
  });

  testWidgets('Cancel throws the form away', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextFormField).first, 'Never saved');
    await tapButton(tester, 'Postpone +1 hour');
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(await tester.runAsync(() => db.select(db.actionsTable).get()), isEmpty);
    await unmount(tester);
  });

  testWidgets('the date edit menu opens from the Start field and edits the form', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(field('Start'));
    await settle(tester);
    expect(find.byType(QuickTimeEditDialog), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await settle(tester);
    expect(find.byType(QuickTimeEditDialog), findsNothing);
    await unmount(tester);
  });

  testWidgets('All day hides the buttons, switching it off shows them again', (
    tester,
  ) async {
    await open(tester);
    expect(find.byTooltip('Postpone +1 hour'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('editorAllDaySwitch')));
    await tester.pump();
    expect(find.byTooltip('Postpone +1 hour'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('editorAllDaySwitch')));
    await tester.pump();
    expect(find.byTooltip('Postpone +1 hour'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('times dragged out on the calendar are kept (no default)', (
    tester,
  ) async {
    final start = DateTime.utc(2030, 5, 6, 8);
    final end = DateTime.utc(2030, 5, 6, 8, 40);
    await open(tester, initialStart: start, initialEnd: end);
    expect(value(tester, 'Start'), start);
    expect(value(tester, 'End'), end);
    await unmount(tester);
  });

  testWidgets('phone: the same buttons, in wrapping groups', (tester) async {
    await open(tester, size: const Size(375, 812));
    final start = value(tester, 'Start')!;
    expect(find.byTooltip('Start'), findsOneWidget);
    expect(find.byTooltip('Postpone +1 hour'), findsOneWidget);
    await tapButton(tester, 'Postpone +1 hour');
    expect(value(tester, 'Start'), start.add(const Duration(hours: 1)));
    await unmount(tester);
  });
}
