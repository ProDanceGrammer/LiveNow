import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/budget_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/budget_files.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/screens/budget_screen.dart';

import '../domain/budget_csv_test.dart'
    show accountsCsv, categoriesCsv, transactionsCsv;

/// Replaces the native file dialogs.
class _FakeFiles extends BudgetFiles {
  _FakeFiles({this.picked = const []});

  final List<PickedFile> picked;
  final saved = <String, String>{};
  Map<String, String>? folder;

  @override
  Future<List<PickedFile>> pickImportFiles() async => picked;

  @override
  Future<String?> saveText(String suggestedName, String text) async {
    saved[suggestedName] = text;
    return 'C:/fake/$suggestedName';
  }

  @override
  Future<String?> saveFolder(Map<String, String> files) async {
    folder = files;
    return 'C:/fake';
  }
}

void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;

  // Drift streams need real time to deliver and a fake-time pump to be seen.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  /// Seeds the database BEFORE the screen exists (writing while the screen's
  /// streams are live deadlocks inside runAsync), then mounts the screen.
  Future<void> pump(
    WidgetTester tester, {
    Future<void> Function()? seed,
    BudgetFiles? files,
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
    addTearDown(db.close);
    if (seed != null) await tester.runAsync(seed);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          if (files != null) budgetFilesProvider.overrideWithValue(files),
        ],
        child: const MaterialApp(home: BudgetScreen()),
      ),
    );
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    resetStackedDialogsForTest();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('budget-switch')),
        matching: find.text(label),
      ),
    );
    await settle(tester);
  }

  Future<List<T>> rows<T>(
    WidgetTester tester,
    Future<List<T>> Function() q,
  ) async => (await tester.runAsync(q))!;

  testWidgets('Accounts tab shows the balance: opening + dated transactions', (
    tester,
  ) async {
    late String acc;
    await pump(
      tester,
      seed: () async {
        final b = BudgetService(db);
        acc = await b.saveAccount(
          name: 'Euro card',
          currency: 'EUR',
          rateToBase: 1,
          openingBalance: 100,
        );
        final cat = await b.saveCategory(
          CategoryInput(
            name: 'Food',
            price: 30,
            accountCountId: acc,
            accountUseId: acc,
          ),
        );
        await b.createTransaction(
          categoryId: cat,
          date: DateTime.now().toUtc().subtract(const Duration(days: 1)),
        );
      },
    );
    await openTab(tester, 'Accounts');

    expect(find.text('Euro card'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(ValueKey('budget-balance-$acc'))).data,
      '70.00 EUR',
    );
    await unmount(tester);
  });

  testWidgets('Overview: totals use top-level categories; board columns', (
    tester,
  ) async {
    await pump(
      tester,
      seed: () async {
        final b = BudgetService(db);
        final acc = await b.saveAccount(
          name: 'Euro',
          currency: 'EUR',
          rateToBase: 1,
        );
        await b.saveCategory(
          CategoryInput(
            name: 'Rent',
            price: 100,
            unitsPerMonth: 1,
            accountCountId: acc,
          ),
        );
        final food = await b.saveCategory(
          CategoryInput(
            name: 'Food',
            price: 10,
            unitsPerMonth: 1,
            accountCountId: acc,
          ),
        );
        await b.createTransaction(
          categoryId: food,
          quantity: 5,
          date: DateTime.now().toUtc().subtract(const Duration(days: 3)),
        );
      },
    );

    // Plan: (100 + 10) x 3 months = 330 spent; fact: 5 x 10 = 50 spent.
    String valueOf(String key) => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data)
        .whereType<String>()
        .firstWhere((s) => s.contains('EUR'));
    expect(valueOf('budget-plan-total'), contains('330.00'));
    expect(valueOf('budget-fact-total'), contains('50.00'));
    // Rent: planned 300, nothing spent => "Plan above actual".
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('budget-board-under')),
        matching: find.text('Rent'),
      ),
      findsOneWidget,
    );
    // Food: spent 50 against a plan of 30 => "Actual above plan".
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('budget-board-over')),
        matching: find.text('Food'),
      ),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('Categories tab: the + button creates a category', (
    tester,
  ) async {
    await pump(tester);
    await openTab(tester, 'Categories');
    await tester.tap(find.byKey(const ValueKey('budget-fab')));
    await settle(tester);

    await tester.enterText(
      find.byKey(const ValueKey('category-name')),
      'Groceries',
    );
    await tester.tap(find.byKey(const ValueKey('category-save')));
    await settle(tester);

    final saved = await rows(
      tester,
      () => db.select(db.budgetCategoriesTable).get(),
    );
    expect(saved.map((c) => c.name), ['Groceries']);
    expect(find.text('Groceries'), findsWidgets);
    await unmount(tester);
  });

  testWidgets(
    'Quick add links to the running action and prefills the quantity',
    (tester) async {
      late String cat, action;
      await pump(
        tester,
        seed: () async {
          final b = BudgetService(db);
          final acc = await b.saveAccount(
            name: 'Euro',
            currency: 'EUR',
            rateToBase: 1,
          );
          cat = await b.saveCategory(
            CategoryInput(name: 'Milk', price: 2, accountCountId: acc),
          );
          await b.createTransaction(categoryId: cat, quantity: 3);
          final actions = ActionService(db);
          action = await actions.createAction(name: 'Shopping');
          await actions.start(action);
        },
      );

      await tester.tap(find.byKey(const ValueKey('budget-fab')));
      await settle(tester);
      // The running action is preselected.
      expect(find.text('Shopping'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tx-category')));
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('pick-category-$cat')));
      await settle(tester);

      // Quantity is that of the previous Milk transaction.
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('tx-quantity')))
            .controller!
            .text,
        '3',
      );
      await tester.tap(find.byKey(const ValueKey('tx-save')));
      await settle(tester);

      final txs = await rows(
        tester,
        () => db.select(db.budgetTransactionsTable).get(),
      );
      expect(txs, hasLength(2));
      expect(txs.where((t) => t.actionId == action), hasLength(1));
      await unmount(tester);
    },
  );

  testWidgets('deleting a transaction shows an Undo that brings it back', (
    tester,
  ) async {
    await pump(
      tester,
      seed: () async {
        final b = BudgetService(db);
        final cat = await b.saveCategory(const CategoryInput(name: 'x'));
        await b.createTransaction(categoryId: cat, name: 'Coffee');
      },
    );
    await openTab(tester, 'Transactions');

    final txId = (await rows(
      tester,
      () => db.select(db.budgetTransactionsTable).get(),
    )).single.id;
    await tester.tap(find.byKey(ValueKey('budget-delete-tx-$txId')));
    await settle(tester);
    expect(
      await rows(tester, () => db.select(db.budgetTransactionsTable).get()),
      isEmpty,
    );

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(
      await rows(tester, () => db.select(db.budgetTransactionsTable).get()),
      hasLength(1),
    );
    await tester.pump(const Duration(seconds: 6));
    await unmount(tester);
  });

  Future<void> chooseMenu(WidgetTester tester, String itemKey) async {
    await tester.tap(find.byKey(const ValueKey('budget-menu')));
    await tester.pump(); // mounts the menu route
    await tester.pump(const Duration(milliseconds: 500)); // its animation
    await tester.tap(find.byKey(ValueKey(itemKey)));
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
  }

  testWidgets('Import: the three Notion CSVs are recognised and summarised', (
    tester,
  ) async {
    final files = _FakeFiles(
      picked: [
        PickedFile('Notion Export - Transactions.csv', transactionsCsv),
        PickedFile('Notion Export - Accounts.csv', accountsCsv),
        PickedFile('Notion Export - Categories.csv', categoriesCsv),
        PickedFile('notes.txt', 'hello'),
      ],
    );
    await pump(tester, files: files);
    await chooseMenu(tester, 'budget-import');

    // Empty budget: no replace question, straight to the summary.
    expect(find.text('Budget import finished'), findsOneWidget);
    expect(find.text('3 accounts'), findsOneWidget);
    expect(find.text('7 categories'), findsOneWidget);
    expect(find.text('3 transactions'), findsOneWidget);
    expect(find.textContaining('without a category'), findsOneWidget);
    expect(find.text('• notes.txt'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('budget-import-ok')));
    await settle(tester);

    final txs = await rows(
      tester,
      () => db.select(db.budgetTransactionsTable).get(),
    );
    expect(txs, hasLength(3));
    await unmount(tester);
  });

  testWidgets('Import over existing data asks first; Cancel keeps it', (
    tester,
  ) async {
    final files = _FakeFiles(
      picked: [PickedFile('Notion Export - Categories.csv', categoriesCsv)],
    );
    await pump(
      tester,
      files: files,
      seed: () async {
        await BudgetService(db).saveCategory(const CategoryInput(name: 'Mine'));
      },
    );
    await chooseMenu(tester, 'budget-import');

    expect(find.text('Replace the budget data?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    final names = (await rows(
      tester,
      () => db.select(db.budgetCategoriesTable).get(),
    )).map((c) => c.name);
    expect(names, ['Mine']);

    await chooseMenu(tester, 'budget-import');
    await tester.tap(find.byKey(const ValueKey('confirm-budget-import')));
    await settle(tester);
    expect(find.text('Budget import finished'), findsOneWidget);
    expect(find.text('7 categories'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('budget-import-ok')));
    await settle(tester);
    await unmount(tester);
  });

  testWidgets('Export: JSON backup and the three CSV files', (tester) async {
    final files = _FakeFiles();
    await pump(
      tester,
      files: files,
      seed: () async {
        await BudgetService(db).saveCategory(const CategoryInput(name: 'Food'));
      },
    );

    await chooseMenu(tester, 'budget-export-json');
    final name = files.saved.keys.single;
    expect(name, matches(RegExp(r'^livenow-budget-\d{4}-\d{2}-\d{2}\.json$')));
    expect(files.saved[name], contains('"format": "livenow-budget"'));
    expect(files.saved[name], contains('"Food"'));
    await tester.pump(const Duration(seconds: 6));

    await chooseMenu(tester, 'budget-export-csv');
    expect(files.folder!.keys, hasLength(3));
    expect(files.folder!['Budget - Categories.csv'], contains('Food'));
    await tester.pump(const Duration(seconds: 6));
    await unmount(tester);
  });
}
