import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/budget_service.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/metric_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/main.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/sync_providers.dart';

/// The phone layout (iPhone 11 Pro: 375 x 812 logical pixels): every section
/// must build and lay out without a framework error (overflow stripes etc.).
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  final errors = <String>[];

  Future<void> pumpPhone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    // Seeded BEFORE mounting (writes under live drift streams deadlock).
    final actions = ActionService(db);
    final metrics = MetricService(db);
    final m1 = await metrics.saveMetric(
      name: 'Sleep enough',
      kind: MetricKind.boolean,
      isMain: true,
    );
    final m2 = await metrics.saveMetric(
      name: 'Exercise',
      kind: MetricKind.count,
      window: MetricWindow.week,
      target: 3,
      leadsToIds: [m1],
    );
    final now = DateTime.now();
    final a = await actions.createAction(
      name: 'A rather long action name that has to wrap on a narrow screen',
      startAt: now.subtract(const Duration(minutes: 20)),
      endAt: now.add(const Duration(hours: 2)),
      metricIds: [m1, m2],
    );
    await actions.createAction(
      name: 'Tomorrow',
      startAt: now.add(const Duration(days: 1)),
      endAt: now.add(const Duration(days: 1, hours: 1)),
    );
    await actions.createAction(
      name: 'All day thing',
      isAllDay: true,
      startAt: DateTime(now.year, now.month, now.day),
    );
    final budget = BudgetService(db);
    final cat = await budget.saveCategory(
      const CategoryInput(name: 'Groceries', price: 25),
    );
    await budget.createTransaction(categoryId: cat, actionId: a);
    await tester.runAsync(() async {});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          syncRoleProvider.overrideWithValue(SyncRole.client),
        ],
        child: const LiveNowApp(),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    resetStackedDialogsForTest();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// Collects framework errors (overflows ...) instead of failing on the first.
  /// Installed inside each test (testWidgets sets its own handler after
  /// setUp); the returned function puts the original handler back.
  void Function() collectErrors() {
    errors.clear();
    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      final text = d.toDiagnosticsNode().toStringDeep();
      final where = RegExp(r'lib/[a-z_/]+[.]dart:[0-9]+')
          .firstMatch(text)
          ?.group(0);
      errors.add(
        '${d.exceptionAsString().split(String.fromCharCode(10)).first}'
        '${where == null ? '' : ' @ $where'}',
      );
    };
    return () => FlutterError.onError = original;
  }

  /// A few bounded frames: a section may keep a ticker running forever.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    // A scrollable tab bar may keep the tab off screen.
    await tester.ensureVisible(find.text(text).first);
    await tester.pump();
    await tester.tap(find.text(text).first);
    await settle(tester);
  }

  testWidgets('the phone shell shows bottom navigation, no rail or menu', (
    tester,
  ) async {
    final restore = collectErrors();
    await pumpPhone(tester);
    final seen = [...errors];
    restore();
    expect(find.byKey(const ValueKey('phone-nav')), findsOneWidget);
    expect(find.byType(MenuBar), findsNothing);
    expect(find.byKey(const ValueKey('phone-menu')), findsOneWidget);
    expect(seen, isEmpty, reason: seen.join(String.fromCharCode(10)));
    await unmount(tester);
  });

  testWidgets('every section lays out at 375 px without errors', (
    tester,
  ) async {
    final restore = collectErrors();
    await pumpPhone(tester);
    final problems = <String>[];
    void check(String where) {
      for (final e in errors.toSet()) {
        problems.add('$where: $e');
      }
      errors.clear();
    }

    check('Actions/Current');
    await tapText(tester, 'Calendar');
    check('Actions/Calendar');
    // The Calendar is full screen on a phone: bring the menus back.
    expect(find.byKey(const ValueKey('phone-nav')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('calendar-full-toggle')));
    await settle(tester);
    expect(find.byKey(const ValueKey('phone-nav')), findsOneWidget);
    await tapText(tester, 'All');
    check('Actions/All');
    await tapText(tester, 'Templates');
    check('Templates');
    await tapText(tester, 'Growth Directions');
    check('Growth/Balance');
    for (final tab in ['List', 'Mindmap']) {
      await tapText(tester, tab);
      check('Growth/$tab');
    }
    await tapText(tester, 'Budget');
    check('Budget/Overview');
    for (final tab in ['Categories', 'Transactions', 'Accounts']) {
      await tapText(tester, tab);
      check('Budget/$tab');
    }
    restore();
    expect(problems, isEmpty, reason: problems.join(String.fromCharCode(10)));
    await unmount(tester);
  });

  testWidgets('dialogs open at 375 px without errors', (tester) async {
    final restore = collectErrors();
    await pumpPhone(tester);
    final problems = <String>[];

    /// Opens a dialog by tapping [target], notes errors, closes it again.
    Future<void> dialog(String where, Finder target) async {
      await tester.tap(target.first);
      await settle(tester);
      for (final e in errors.toSet()) {
        problems.add('$where: $e');
      }
      errors.clear();
      // Tap the barrier outside the dialog to close it.
      await tester.tapAt(const Offset(2, 2));
      await settle(tester);
      resetStackedDialogsForTest();
    }

    // New action (FAB) and an existing one (card).
    await dialog('Action editor (new)', find.byTooltip('New action'));
    await dialog(
      'Action editor (existing)',
      find.textContaining('A rather long'),
    );
    // The sync dialog (client role).
    await dialog('Sync dialog', find.byKey(const ValueKey('sync-status')));
    // Growth: a direction (List tab) and the new-direction dialog.
    await tapText(tester, 'Growth Directions');
    await tapText(tester, 'List');
    await dialog('Growth direction (existing)', find.text('Exercise'));
    await dialog(
      'Growth direction (new)',
      find.byTooltip('New growth direction'),
    );
    // Templates (a tab of Actions): the editor.
    await tapText(tester, 'Actions');
    await tapText(tester, 'Templates');
    await dialog('Template editor', find.byTooltip('New template'));
    // Budget: category, transaction, account, settings.
    await tapText(tester, 'Budget');
    await tapText(tester, 'Categories');
    await dialog('Budget category', find.text('Groceries'));
    await tapText(tester, 'Transactions');
    await dialog('Budget transaction', find.textContaining('Groceries'));
    await tapText(tester, 'Accounts');
    await dialog(
      'Budget settings',
      find.byKey(const ValueKey('budget-settings')),
    );
    restore();
    expect(problems, isEmpty, reason: problems.join(String.fromCharCode(10)));
    await unmount(tester);
  });
}
