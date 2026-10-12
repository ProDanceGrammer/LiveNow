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
import 'package:livenow/ui/open_entity.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/screens/settings_screen.dart';
import 'package:livenow/ui/sync_providers.dart';
import 'package:livenow/ui/widgets/action_editor.dart';
import 'package:livenow/ui/widgets/budget_dialogs.dart';
import 'package:livenow/ui/widgets/action_picker_dialog.dart';

/// Every screen and dialog with a text field, opened on a 375 x 812 phone with
/// the on-screen keyboard (336 px) up. For each one: no framework error
/// (overflow stripes ...), the focused field is above the keyboard, and the
/// dialog's pinned buttons (Save / Cancel) are on screen above it.
const _kb = 336.0;
const _w = 375.0;
const _h = 812.0;

void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  final errors = <String>[];

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

  Future<void> settle(WidgetTester tester, [int ms = 600]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  late String actionId, directionId, accountId, categoryId;

  Future<void> pumpHarness(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(_w, _h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(tester.view.resetViewInsets);
    db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
    addTearDown(db.close);
    await tester.runAsync(() async {
      actionId = await ActionService(db).createAction(
        name: 'An action',
        startAt: DateTime.now().add(const Duration(hours: 2)),
        endAt: DateTime.now().add(const Duration(hours: 3)),
      );
      directionId = await MetricService(db).saveMetric(
        name: 'A direction',
        kind: MetricKind.count,
        window: MetricWindow.week,
        target: 3,
      );
      final b = BudgetService(db);
      accountId = await b.saveAccount(
        name: 'Card',
        currency: 'EUR',
        rateToBase: 1,
      );
      categoryId = await b.saveCategory(
        CategoryInput(name: 'Food', price: 5, accountCountId: accountId),
      );
      await b.createTransaction(categoryId: categoryId, name: 'Bread');
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          syncRoleProvider.overrideWithValue(SyncRole.client),
        ],
        child: MaterialApp(home: home),
      ),
    );
    await settle(tester, 300);
  }

  Future<void> unmount(WidgetTester tester) async {
    resetStackedDialogsForTest();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// The rect of the widget that holds keyboard focus (null = none).
  Rect? focusedRect() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    // Only a text field counts (otherwise the focus is a whole page's scope).
    if (ctx == null || ctx.widget is! EditableText) return null;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Checks one open surface; [name] labels the report.
  void check(
    WidgetTester tester,
    String name,
    List<String> problems, {
    List<Finder> pinned = const [],
  }) {
    for (final e in errors.toSet()) {
      problems.add('$name: $e');
    }
    errors.clear();
    final visibleBottom = _h - _kb;
    final f = focusedRect();
    if (f != null && f.bottom > visibleBottom + 1) {
      problems.add(
        '$name: the focused field ends at ${f.bottom.round()} under the keyboard (${visibleBottom.round()})',
      );
    }
    for (final finder in pinned) {
      if (finder.evaluate().isEmpty) continue;
      final r = tester.getRect(finder.first);
      if (r.bottom > visibleBottom + 1 || r.top < 0) {
        problems.add(
          '$name: a pinned button is at ${r.top.round()}-${r.bottom.round()}, the visible area ends at ${visibleBottom.round()}',
        );
      }
    }
  }

  testWidgets('dialogs with the keyboard up', (tester) async {
    final restore = collectErrors();
    addTearDown(restore);
    await pumpHarness(
      tester,
      Scaffold(
        body: Consumer(
          builder: (context, ref, _) => Wrap(
            children: [
              TextButton(
                key: const ValueKey('open-action-new'),
                onPressed: () => ActionEditorDialog.show(context),
                child: const Text('x'),
              ),
              TextButton(
                key: const ValueKey('open-action-existing'),
                onPressed: () => openActionById(context, ref, actionId),
                child: const Text('y'),
              ),
              TextButton(
                key: const ValueKey('open-direction'),
                onPressed: () => openDirectionById(context, ref, directionId),
                child: const Text('z'),
              ),
              TextButton(
                key: const ValueKey('open-category'),
                onPressed: () => BudgetCategoryDialog.show(context),
                child: const Text('c'),
              ),
              TextButton(
                key: const ValueKey('open-account'),
                onPressed: () => BudgetAccountDialog.show(context),
                child: const Text('a'),
              ),
              TextButton(
                key: const ValueKey('open-tx'),
                onPressed: () => BudgetTransactionDialog.show(
                  context,
                  categoryId: categoryId,
                ),
                child: const Text('t'),
              ),
              TextButton(
                key: const ValueKey('open-action-picker'),
                onPressed: () => ActionPickerDialog.show(context),
                child: const Text('p'),
              ),
            ],
          ),
        ),
      ),
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: _kb);
    await settle(tester, 300);

    final problems = <String>[];
    final saveButtons = [
      find.widgetWithText(FilledButton, 'Save'),
      find.byKey(const ValueKey('category-save')),
      find.byKey(const ValueKey('account-save')),
      find.byKey(const ValueKey('tx-save')),
    ];

    Future<void> dialog(String name, String key) async {
      try {
        await tester.tap(find.byKey(ValueKey(key)));
        await settle(tester, 700);
        check(tester, name, problems, pinned: saveButtons);
        // Focus the first and the LAST text field: each must end up above the
        // keyboard (the form scrolls it into view).
        final fields = find.byType(EditableText);
        final count = fields.evaluate().length;
        if (count > 0) {
          for (final i in {0, count - 1}) {
            // The form can change under a tap: look the field up again, and
            // scroll it into view first, as a finger would.
            if (i >= fields.evaluate().length) continue;
            await tester.ensureVisible(fields.at(i));
            await tester.pump();
            await tester.tap(fields.at(i), warnIfMissed: false);
            await settle(tester, 500);
            check(
              tester,
              '$name (field ${i + 1}/$count)',
              problems,
              pinned: saveButtons,
            );
          }
        }
        // Close it again: the barrier is outside the visible area, so use
        // Cancel or the back route.
        final cancel = find.text('Cancel');
        if (cancel.evaluate().isNotEmpty) {
          await tester.tap(cancel.last, warnIfMissed: false);
        } else {
          await tester.pageBack();
        }
        await settle(tester, 300);
      } catch (e) {
        problems.add('$name: the check itself threw: $e');
      }
      resetStackedDialogsForTest();
    }

    await dialog('Action editor (new)', 'open-action-new');
    await dialog('Action editor (existing)', 'open-action-existing');
    await dialog('Growth direction (existing)', 'open-direction');
    await dialog('Budget category (new)', 'open-category');
    await dialog('Budget account (new)', 'open-account');
    await dialog('Budget transaction (new)', 'open-tx');
    await dialog('Action picker', 'open-action-picker');

    restore();
    expect(problems, isEmpty, reason: problems.join(String.fromCharCode(10)));
    await unmount(tester);
  });

  testWidgets('screens with a search field or text input, keyboard up', (
    tester,
  ) async {
    final restore = collectErrors();
    await pumpHarness(tester, const SettingsScreen());
    tester.view.viewInsets = const FakeViewPadding(bottom: _kb);
    await settle(tester, 300);
    final problems = <String>[];
    check(tester, 'Settings', problems);
    restore();
    expect(problems, isEmpty, reason: problems.join(String.fromCharCode(10)));
    await unmount(tester);
  });

  testWidgets('the phone app: search fields on every tab with the keyboard up', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(_w, _h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(tester.view.resetViewInsets);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.runAsync(() async {
      await ActionService(db).createAction(
        name: 'An action',
        startAt: DateTime.now().add(const Duration(hours: 2)),
        endAt: DateTime.now().add(const Duration(hours: 3)),
      );
      await MetricService(db)
          .saveMetric(name: 'A direction', kind: MetricKind.boolean);
      final b = BudgetService(db);
      final c = await b.saveCategory(
        const CategoryInput(name: 'Food', price: 5),
      );
      await b.createTransaction(categoryId: c, name: 'Bread');
    });
    final restore = collectErrors();
    addTearDown(restore);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          syncRoleProvider.overrideWithValue(SyncRole.client),
        ],
        child: const LiveNowApp(),
      ),
    );
    await settle(tester, 800);
    tester.view.viewInsets = const FakeViewPadding(bottom: _kb);
    await settle(tester, 300);

    final problems = <String>[];
    Future<void> tapText(String text) async {
      await tester.ensureVisible(find.text(text).first);
      await tester.tap(find.text(text).first, warnIfMissed: false);
      await settle(tester, 500);
    }

    Future<void> focusField(String name, Finder field) async {
      if (field.evaluate().isEmpty) {
        problems.add('$name: the search field was not found');
        return;
      }
      await tester.tap(field.first);
      await settle(tester, 400);
      check(tester, name, problems);
    }

    /// A step that throws is a finding too (and must not hide the others).
    Future<void> step(String name, Future<void> Function() run) async {
      try {
        await run();
      } catch (e) {
        problems.add(
          '$name: the step threw: ${e.toString().split(String.fromCharCode(10)).first}',
        );
      }
    }

    await step('Current search', () async {
      await tester.tap(find.byKey(const ValueKey('current-search-toggle')));
      await settle(tester, 400);
      check(tester, 'Current search', problems);
    });
    await step('All', () async {
      await tapText('All');
      check(tester, 'All', problems);
      await focusField('All search', find.byType(TextField));
    });
    await step('Templates', () async {
      await tapText('Templates');
      await focusField(
        'Templates search',
        find.byKey(const ValueKey('templates-search')),
      );
    });
    await step('Mindmap', () async {
      await tapText('Growth Directions');
      await tapText('Mindmap');
      await tester.tap(
        find.byTooltip('Find a direction').first,
        warnIfMissed: false,
      );
      await settle(tester, 500);
      check(tester, 'Mindmap search', problems);
    });
    await step('Budget', () async {
      await tapText('Budget');
      await tapText('Categories');
      await focusField(
        'Budget categories search',
        find.byKey(const ValueKey('budget-categories-search')),
      );
      await tapText('Transactions');
      await focusField(
        'Budget transactions search',
        find.byKey(const ValueKey('budget-transactions-search')),
      );
    });

    restore();
    expect(problems, isEmpty, reason: problems.join(String.fromCharCode(10)));
    await unmount(tester);
  });
}
