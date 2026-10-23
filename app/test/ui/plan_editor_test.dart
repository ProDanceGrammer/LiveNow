import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:livenow/core/ids.dart';
import 'package:livenow/core/time_codec.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/budget_service.dart';
import 'package:livenow/domain/plan_rules.dart';
import 'package:livenow/domain/plan_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/plan_providers.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/screens/budget_screen.dart';
import 'package:livenow/ui/views/calendar_view.dart';
import 'package:livenow/ui/widgets/param_icons.dart' show Param, ParamIcon;
import 'package:livenow/ui/widgets/tx_templates.dart'
    show TransactionTemplateDialog;

/// The plan item editor (template name, switch, duplicate, Previous / Next /
/// transactions) and the transaction templates panel in Budget > Transactions.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;

  Future<void> settle(WidgetTester tester, [int ms = 300]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    resetStackedDialogsForTest();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<String> template(WidgetTester tester, String name) async =>
      (await tester.runAsync(() async {
        final id = newId();
        await db
            .into(db.actionTemplatesTable)
            .insert(
              ActionTemplatesTableCompanion.insert(
                id: id,
                name: name,
                payload: jsonEncode({'name': name}),
              ),
            );
        return id;
      }))!;

  Future<void> openEditor(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('calendar-planning-toggle')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('plan-bar-add')));
    await settle(tester);
  }

  late String catId;

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
    addTearDown(db.close);
    await tester.runAsync(() async {
      final b = BudgetService(db);
      final acc = await b.saveAccount(
        name: 'Cash',
        currency: 'EUR',
        rateToBase: 1,
      );
      catId = await b.saveCategory(
        CategoryInput(name: 'Groceries', price: 600, accountCountId: acc),
      );
    });
  }

  Future<void> pumpCalendar(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          calendarVisibleHoursProvider.overrideWith((ref) => 24),
        ],
        child: const MaterialApp(home: Scaffold(body: CalendarView())),
      ),
    );
    await settle(tester);
  }

  Future<void> pickTemplate(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(const ValueKey('plan-template')));
    await settle(tester, 200);
    await tester.tap(find.text(name).last);
    await settle(tester, 200);
  }

  String nameText(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const ValueKey('plan-name')))
      .controller!
      .text;

  testWidgets('a template fills the name; the button re-applies it', (
    tester,
  ) async {
    await mount(tester);
    await template(tester, 'Swim');
    await template(tester, 'Run');
    await pumpCalendar(tester);
    await openEditor(tester);

    await pickTemplate(tester, 'Swim');
    expect(nameText(tester), 'Swim');
    expect(find.byKey(const ValueKey('plan-name-from-template')), findsNothing);

    // The name still follows the template while it equals the old one.
    await pickTemplate(tester, 'Run');
    expect(nameText(tester), 'Run');

    // A name typed by hand is kept; the button offers the template's name.
    await tester.enterText(find.byKey(const ValueKey('plan-name')), 'Morning');
    await tester.pump();
    await pickTemplate(tester, 'Swim');
    expect(nameText(tester), 'Morning');
    await tester.tap(find.byKey(const ValueKey('plan-name-from-template')));
    await tester.pump();
    expect(nameText(tester), 'Swim');
    await unmount(tester);
  });

  testWidgets('the pencil next to the template opens its editor', (tester) async {
    await mount(tester);
    await template(tester, 'Swim');
    await pumpCalendar(tester);
    await openEditor(tester);

    // No template chosen: the pencil is greyed out.
    expect(
      tester
          .widget<IconButton>(
            find.descendant(
              of: find.byKey(const ValueKey('plan-template-edit')),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    await pickTemplate(tester, 'Swim');
    await tester.tap(find.byKey(const ValueKey('plan-template-edit')));
    await settle(tester, 600);
    // The template editor is on top, showing the template's name.
    expect(find.widgetWithText(TextFormField, 'Swim'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('only the switch toggles "forever"; a time row duplicates', (
    tester,
  ) async {
    await mount(tester);
    await pumpCalendar(tester);
    await openEditor(tester);

    await tester.tap(find.text('Keep creating actions (forever)'));
    await tester.pump();
    expect(
      tester.widget<Switch>(find.byKey(const ValueKey('plan-forever'))).value,
      isFalse,
    );
    await tester.tap(find.byKey(const ValueKey('plan-forever')));
    await tester.pump();
    expect(
      tester.widget<Switch>(find.byKey(const ValueKey('plan-forever'))).value,
      isTrue,
    );

    expect(find.byKey(const ValueKey('plan-row-day-1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('plan-row-duplicate-0')));
    await tester.pump();
    expect(find.byKey(const ValueKey('plan-row-day-1')), findsOneWidget);
    // The labels are written out, not truncated hints.
    expect(find.text('Minutes'), findsWidgets);
    expect(find.text('Own name'), findsWidgets);
    await unmount(tester);
  });

  testWidgets('Previous / Next and a transaction save with the time row', (
    tester,
  ) async {
    await mount(tester);
    final tx = (await tester.runAsync(
      () => BudgetService(db).saveTxTemplate(
        name: 'Groceries',
        categoryId: catId,
        unitPrice: 600,
      ),
    ))!;
    await pumpCalendar(tester);
    await openEditor(tester);

    await tester.enterText(find.byKey(const ValueKey('plan-name')), 'Bazaar');
    await tester.tap(find.byKey(const ValueKey('row-0-extras-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('row-0-add-prev')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('row-0-prev-0-name')),
      'Get ready',
    );
    await tester.tap(find.byKey(const ValueKey('row-0-add-next')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('row-0-next-0-name')),
      'Unpack',
    );
    await tester.enterText(
      find.byKey(const ValueKey('row-0-next-0-gap')),
      '10',
    );
    await tester.tap(find.byKey(const ValueKey('row-0-tx-add')));
    await settle(tester, 200);
    await tester.tap(find.byKey(ValueKey('txt-pick-$tx')));
    await settle(tester, 200);
    expect(find.widgetWithText(InputChip, 'Groceries'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('plan-save')));
    await settle(tester);

    final row = (await tester.runAsync(
      () => db.select(db.planItemsTable).getSingle(),
    ))!;
    final occ = CycleRule.fromJson(
      Map<String, Object?>.from(jsonDecode(row.rule) as Map),
    ).occurrences.single;
    expect(occ.extras.prev.single.name, 'Get ready');
    expect(occ.extras.next.single.name, 'Unpack');
    expect(occ.extras.next.single.gapMinutes, 10);
    expect(occ.extras.txTemplateIds, [tx]);
    await unmount(tester);
  });

  testWidgets('Transactions: the templates button shows the list', (
    tester,
  ) async {
    await mount(tester);
    final tx = (await tester.runAsync(
      () => BudgetService(db).saveTxTemplate(
        name: 'Market',
        categoryId: catId,
        quantity: 2,
        unitPrice: 50,
      ),
    ))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: BudgetScreen()),
      ),
    );
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('budget-switch')),
        matching: find.text('Transactions'),
      ),
    );
    await settle(tester);

    expect(find.byKey(const ValueKey('tx-templates-panel')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tx-templates-toggle')));
    await settle(tester);
    expect(find.byKey(const ValueKey('tx-templates-panel')), findsOneWidget);
    expect(find.text('Market'), findsOneWidget);
    expect(find.textContaining('Groceries · 2 × 50'), findsOneWidget);

    // "Create a transaction now" makes a real one.
    await tester.tap(find.byKey(ValueKey('tx-template-use-$tx')));
    await settle(tester);
    final txs = (await tester.runAsync(
      () => db.select(db.budgetTransactionsTable).get(),
    ))!;
    expect(txs.single.name, 'Market');
    expect(txs.single.quantity, 2);

    // Delete, then Undo brings it back.
    await tester.tap(find.byKey(ValueKey('tx-template-delete-$tx')));
    await settle(tester);
    expect(find.byKey(ValueKey('tx-template-$tx')), findsNothing);
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(find.byKey(ValueKey('tx-template-$tx')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('Transactions: many templates scroll in a bounded list, no overflow', (
    tester,
  ) async {
    await mount(tester);
    await tester.runAsync(() async {
      final budget = BudgetService(db);
      String? first;
      for (var i = 0; i < 40; i++) {
        final id = await budget.saveTxTemplate(
          name: 'Template $i',
          categoryId: catId,
          unitPrice: 10,
        );
        first ??= id;
      }
      await budget.createTransactionFromTemplate(first!);
    });
    tester.view.physicalSize = const Size(1000, 700);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: BudgetScreen()),
      ),
    );
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('budget-switch')),
        matching: find.text('Transactions'),
      ),
    );
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('tx-templates-toggle')));
    await settle(tester);

    // A RenderFlex overflow would fail the test by itself; the list is also
    // capped (30 % of the window) and scrolls to reach the last template.
    final list = find.byKey(const ValueKey('tx-templates-list'));
    expect(tester.getSize(list).height, lessThanOrEqualTo(700 * 0.3 + 0.5));
    // Sorted by name, the last one is 'Template 9': off screen until scrolled to.
    expect(find.text('Template 9'), findsNothing);
    await tester.drag(list, const Offset(0, -6000));
    await tester.pump();
    expect(find.text('Template 9'), findsOneWidget);
    // The transaction list below is still on screen.
    expect(find.byKey(const ValueKey('tx-totals')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a transaction chip in the plan editor opens its template to edit', (
    tester,
  ) async {
    await mount(tester);
    final tx = (await tester.runAsync(
      () => BudgetService(db).saveTxTemplate(
        name: 'Groceries',
        categoryId: catId,
        unitPrice: 600,
      ),
    ))!;
    await pumpCalendar(tester);
    await openEditor(tester);
    await tester.tap(find.byKey(const ValueKey('row-0-extras-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('row-0-tx-add')));
    await settle(tester, 200);
    await tester.tap(find.byKey(ValueKey('txt-pick-$tx')));
    await settle(tester, 200);

    final chip = find.byKey(ValueKey('row-0-tx-add-open-$tx'));
    expect(chip, findsOneWidget);
    await tester.tap(chip);
    await settle(tester, 200);
    // The template dialog opens on top, filled with the template.
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('txt-name'))).controller!.text,
      'Groceries',
    );
    await tester.enterText(find.byKey(const ValueKey('txt-name')), 'Bazaar food');
    await tester.tap(find.byKey(const ValueKey('txt-save')));
    await settle(tester, 300);

    // The chip shows the new name and the template was changed (same id).
    expect(find.widgetWithText(InputChip, 'Bazaar food'), findsOneWidget);
    final saved = (await tester.runAsync(
      () => db.select(db.budgetTxTemplatesTable).getSingle(),
    ))!;
    expect(saved.id, tx);
    expect(saved.name, 'Bazaar food');
    await unmount(tester);
  });

  testWidgets('the editor fits a 375 px phone with every section open', (
    tester,
  ) async {
    await mount(tester);
    tester.view.physicalSize = const Size(375, 812);
    await pumpCalendar(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CalendarView)),
    );
    container.read(calendarPlanningProvider.notifier).state = true;
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('plan-bar-add')));
    await settle(tester);
    Future<void> tapKey(String key) async {
      final f = find.byKey(ValueKey(key));
      await tester.ensureVisible(f);
      await tester.pump();
      await tester.tap(f);
      await tester.pump();
    }

    await tapKey('row-0-extras-toggle');
    await tapKey('row-0-add-prev');
    await tapKey('row-0-add-next');
    await tapKey('plan-row-duplicate-0');
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('the Minutes field shows the average and how yours differs', (
    tester,
  ) async {
    await mount(tester);
    await template(tester, 'Swim');
    // Two finished 45-minute runs of "Swim" in the last days.
    await tester.runAsync(() async {
      final now = DateTime.now().toUtc();
      for (var d = 1; d <= 2; d++) {
        final start = now.subtract(Duration(days: d, hours: 1));
        final id = await ActionService(db).createAction(
          name: 'Swim',
          startAt: start,
          endAt: start.add(const Duration(minutes: 45)),
        );
        await (db.update(db.actionsTable)..where((t) => t.id.equals(id))).write(
          ActionsTableCompanion(
            done: const Value(true),
            completedAt: Value(dateTimeToDb(now)!),
          ),
        );
      }
    });
    await pumpCalendar(tester);
    await openEditor(tester);

    // No average until the item is named / a template is chosen.
    expect(find.byKey(const ValueKey('plan-row-avg-0')), findsNothing);
    await pickTemplate(tester, 'Swim');
    await settle(tester);
    Text note() => tester.widget<Text>(find.byKey(const ValueKey('plan-row-avg-0')));
    expect(note().data, 'Average of finished runs: 45 min');

    await tester.enterText(find.byKey(const ValueKey('plan-row-duration-0')), '30');
    await tester.pump();
    expect(note().data, contains('yours is 15 min shorter'));
    await tester.enterText(find.byKey(const ValueKey('plan-row-duration-0')), '45');
    await tester.pump();
    expect(note().data, 'Average of finished runs: 45 min');
    await tester.enterText(find.byKey(const ValueKey('plan-row-duration-0')), '60');
    await tester.pump();
    expect(note().data, contains('yours is 15 min longer'));
    await unmount(tester);
  });

  testWidgets('a time row can be all day: no time or minutes, saved in the rule', (
    tester,
  ) async {
    await mount(tester);
    await pumpCalendar(tester);
    await openEditor(tester);
    await tester.enterText(find.byKey(const ValueKey('plan-name')), 'Rest day');

    expect(find.byKey(const ValueKey('plan-row-time-0')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('plan-row-allday-0')));
    await tester.pump();
    expect(find.byKey(const ValueKey('plan-row-time-0')), findsNothing);
    expect(find.byKey(const ValueKey('plan-row-duration-0')), findsNothing);

    // Previous / Next do not apply; Transactions do.
    await tester.tap(find.byKey(const ValueKey('row-0-extras-toggle')));
    await tester.pump();
    expect(find.byKey(const ValueKey('row-0-add-prev')), findsNothing);
    expect(find.byKey(const ValueKey('row-0-tx-add')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('plan-save')));
    await settle(tester);
    final row = (await tester.runAsync(
      () => db.select(db.planItemsTable).getSingle(),
    ))!;
    final occ = CycleRule.fromJson(
      Map<String, Object?>.from(jsonDecode(row.rule) as Map),
    ).occurrences.single;
    expect(occ.allDay, isTrue);
    await unmount(tester);
  });

  group('transaction template dialog', () {
    late String bakeryId;

    Future<void> openDialog(WidgetTester tester) async {
      await mount(tester);
      bakeryId = (await tester.runAsync(() async {
        final acc = await db.select(db.budgetAccountsTable).getSingle();
        return BudgetService(db).saveCategory(
          CategoryInput(name: 'Bakery', price: 5, accountCountId: acc.id),
        );
      }))!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => TransactionTemplateDialog.show(context),
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

    Future<void> pick(WidgetTester tester, String id) async {
      await tester.tap(find.byKey(const ValueKey('txt-category')));
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('pick-category-$id')));
      await settle(tester);
    }

    String nameText(WidgetTester tester) => tester
        .widget<TextField>(find.byKey(const ValueKey('txt-name')))
        .controller!
        .text;

    testWidgets('the category is the first field and uses the category icon', (
      tester,
    ) async {
      await openDialog(tester);
      final category = tester.getTopLeft(
        find.byKey(const ValueKey('txt-category')),
      );
      final name = tester.getTopLeft(find.byKey(const ValueKey('txt-name')));
      expect(category.dy, lessThan(name.dy));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('txt-category')),
          matching: find.byWidgetPredicate(
            (w) => w is ParamIcon && w.param == Param.categories,
          ),
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.category_outlined), findsNothing);
      await unmount(tester);
    });

    testWidgets('picking a category names the transaction after it', (
      tester,
    ) async {
      await openDialog(tester);
      expect(nameText(tester), '');
      await pick(tester, catId);
      expect(nameText(tester), 'Groceries');
      // Still the auto name: another category replaces it.
      await pick(tester, bakeryId);
      expect(nameText(tester), 'Bakery');
      await unmount(tester);
    });

    testWidgets('a name the user typed is never overwritten', (tester) async {
      await openDialog(tester);
      await tester.enterText(find.byKey(const ValueKey('txt-name')), 'Milk');
      await tester.pump();
      await pick(tester, catId);
      expect(nameText(tester), 'Milk');
      await unmount(tester);
    });

    testWidgets('a cleared name can take the category name back in one tap', (
      tester,
    ) async {
      await openDialog(tester);
      expect(find.byKey(const ValueKey('txt-name-from-category')), findsNothing);
      await pick(tester, catId);
      await tester.enterText(find.byKey(const ValueKey('txt-name')), '');
      await tester.pump();
      expect(find.byKey(const ValueKey('txt-name-from-category')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('txt-name-from-category')));
      await tester.pump();
      expect(nameText(tester), 'Groceries');
      expect(find.byKey(const ValueKey('txt-name-from-category')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('txt-save')));
      await settle(tester);
      final saved = (await tester.runAsync(
        () => db.select(db.budgetTxTemplatesTable).getSingle(),
      ))!;
      expect(saved.name, 'Groceries');
      expect(saved.categoryId, catId);
      await unmount(tester);
    });
  });

  testWidgets('the Plan items list is searched by name and collection, any case', (
    tester,
  ) async {
    await mount(tester);
    final ids = (await tester.runAsync(() async {
      final plans = PlanService(db, ActionService(db));
      final sport = await plans.saveCollection(name: 'Sport');
      PlanItemInput item(String name, [List<String> c = const []]) =>
          PlanItemInput(
            name: name,
            kind: PlanKind.cycle,
            startDate: planDate(2026, 10, 19),
            cycle: const CycleRule(
              cycleDays: 1,
              occurrences: [CycleOccurrence(day: 0, startMin: 540, durationMin: 30)],
            ),
            collectionIds: c,
          );
      return [
        await plans.saveItem(item('Gym', [sport])),
        await plans.saveItem(item('Бігати вранці')),
        await plans.saveItem(item('Piano')),
      ];
    }))!;
    await pumpCalendar(tester);
    await tester.tap(find.byKey(const ValueKey('calendar-planning-toggle')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('plan-bar-items')));
    await settle(tester);

    Finder tile(int i) => find.byKey(ValueKey('plan-item-${ids[i]}'));
    Future<void> search(String text) async {
      await tester.enterText(
        find.byKey(const ValueKey('plan-items-search')),
        text,
      );
      await tester.pump();
    }

    expect(tile(0), findsOneWidget);
    expect(tile(1), findsOneWidget);
    expect(tile(2), findsOneWidget);

    await search('GYM'); // by name, upper case
    expect(tile(0), findsOneWidget);
    expect(tile(1), findsNothing);
    expect(tile(2), findsNothing);

    await search('sport'); // by the collection's name
    expect(tile(0), findsOneWidget);
    expect(tile(2), findsNothing);

    await search('БІГ'); // Cyrillic, other case
    expect(tile(1), findsOneWidget);
    expect(tile(0), findsNothing);

    await search('  pia  nо '); // every word must match: 'nо' (Cyrillic о) does not
    expect(find.byKey(const ValueKey('plan-items-no-match')), findsOneWidget);
    expect(tile(2), findsNothing);

    await search('zzz');
    expect(find.byKey(const ValueKey('plan-items-no-match')), findsOneWidget);

    await search(''); // cleared: everything is back
    expect(find.byKey(const ValueKey('plan-items-no-match')), findsNothing);
    expect(tile(0), findsOneWidget);
    expect(tile(1), findsOneWidget);
    expect(tile(2), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a weekly item keeps its start date and weekdays when saved again', (
    tester,
  ) async {
    await mount(tester);
    // Starts on a WEDNESDAY (21 Oct 2026): Wed 09:00 and Fri 10:00.
    final id = (await tester.runAsync(
      () => PlanService(db, ActionService(db)).saveItem(
        PlanItemInput(
          name: 'Gym',
          kind: PlanKind.cycle,
          startDate: planDate(2026, 10, 21),
          cycle: const CycleRule(
            cycleDays: 7,
            occurrences: [
              CycleOccurrence(day: 0, startMin: 540, durationMin: 30),
              CycleOccurrence(day: 2, startMin: 600, durationMin: 30),
            ],
          ),
        ),
      ),
    ))!;
    await pumpCalendar(tester);
    await tester.tap(find.byKey(const ValueKey('calendar-planning-toggle')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('plan-bar-items')));
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('plan-item-$id')));
    await settle(tester);

    // The rows show weekdays, not "days after the start".
    final weekdayOfRow0 = tester.widget<DropdownButton<int>>(
      find.byKey(const ValueKey('plan-row-day-0')),
    );
    expect(weekdayOfRow0.value, 2); // Wed
    await tester.tap(find.byKey(const ValueKey('plan-save')));
    await settle(tester);

    final row = (await tester.runAsync(
      () => db.select(db.planItemsTable).getSingle(),
    ))!;
    expect(row.startDate, '2026-10-21'); // not moved to the Monday
    final occ = CycleRule.fromJson(
      Map<String, Object?>.from(jsonDecode(row.rule) as Map),
    ).occurrences;
    expect([for (final o in occ) o.day], [0, 2]); // still Wed and Fri
    await unmount(tester);
  });
}
