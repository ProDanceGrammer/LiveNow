import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/time_codec.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/budget_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/account_icon_codec.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/screens/budget_screen.dart';
import 'package:livenow/ui/widgets/account_icon.dart';
import 'package:livenow/ui/widgets/budget_dialogs.dart';
import 'package:livenow/ui/widgets/param_icons.dart';

/// A real PNG of [w] x [h] pixels, drawn with dart:ui.
Future<Uint8List> _png(int w, int h) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = const Color(0xFF2E7D32),
  );
  canvas.drawCircle(
    Offset(w / 2, h / 2),
    h / 4,
    Paint()..color = const Color(0xFFFFFFFF),
  );
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Future<void> Function()? seed,
    Size size = const Size(1400, 900),
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = size;
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
        overrides: [databaseProvider.overrideWithValue(db), ...overrides],
        child: MaterialApp(home: home),
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

  Finder paramIcon(Param p) =>
      find.byWidgetPredicate((w) => w is ParamIcon && w.param == p);

  // ---- account pictures ---------------------------------------------------

  testWidgets('an image becomes a 96 px square PNG in base64 and back', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final text = await encodeAccountIcon(await _png(300, 120));
      final bytes = decodeAccountIcon(text)!;
      // PNG signature.
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = (await codec.getNextFrame()).image;
      expect((frame.width, frame.height), (96, 96)); // centre-cropped square
      expect(text.length, lessThan(kAccountIconMaxChars));
      frame.dispose();
      codec.dispose();
    });
  });

  testWidgets('unreadable, huge and damaged pictures are refused or ignored', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await expectLater(
        encodeAccountIcon(Uint8List.fromList([1, 2, 3, 4, 5])),
        throwsA(isA<AccountIconException>()),
      );
      await expectLater(
        encodeAccountIcon(Uint8List(kAccountIconMaxFileBytes + 1)),
        throwsA(isA<AccountIconException>()),
      );
    });
    expect(decodeAccountIcon(null), isNull);
    expect(decodeAccountIcon(''), isNull);
    expect(decodeAccountIcon('***not base64***'), isNull);
    expect(decodeAccountIcon('A' * (kAccountIconMaxChars + 1)), isNull);
  });

  testWidgets('AccountIcon shows the purse when there is no picture', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AccountIcon(size: 30))),
    );
    expect(paramIcon(Param.accounts), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('the account dialog picks, saves and removes a picture', (
    tester,
  ) async {
    late Uint8List png;
    await tester.runAsync(() async => png = await _png(64, 64));
    String? accountId;
    await pump(
      tester,
      const BudgetScreen(),
      seed: () async {
        accountId = await BudgetService(db)
            .saveAccount(name: 'Euro card', currency: 'EUR', rateToBase: 1);
      },
      overrides: [accountIconPickerProvider.overrideWithValue(() async => png)],
    );
    await openTab(tester, 'Accounts');
    // No picture yet: the purse.
    expect(paramIcon(Param.accounts), findsWidgets);

    await tester.tap(find.byKey(ValueKey('budget-account-$accountId')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('account-icon-pick')));
    await settle(tester);
    expect(find.byKey(const ValueKey('account-icon-remove')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('account-save')));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    // The dialog is closed again.
    expect(find.byKey(const ValueKey('account-save')), findsNothing);

    var row = (await tester.runAsync(
      () => db.select(db.budgetAccountsTable).getSingle(),
    ))!;
    expect(row.icon, isNotNull);
    expect(decodeAccountIcon(row.icon), isNotNull);
    // The picture is shown in the Accounts list now.
    expect(find.byType(Image), findsWidgets);

    // Removing it again.
    await tester.tap(find.byKey(ValueKey('budget-account-$accountId')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('account-icon-remove')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('account-save')));
    await settle(tester);
    row = (await tester.runAsync(
      () => db.select(db.budgetAccountsTable).getSingle(),
    ))!;
    expect(row.icon, isNull);
    await unmount(tester);
  });

  testWidgets('a refused file shows the reason and saves nothing', (
    tester,
  ) async {
    await pump(
      tester,
      const BudgetScreen(),
      seed: () async {
        await BudgetService(db)
            .saveAccount(name: 'Cash', currency: 'TRY', rateToBase: 40);
      },
      overrides: [
        accountIconPickerProvider.overrideWithValue(
          () async => Uint8List.fromList([9, 9, 9]),
        ),
      ],
    );
    await openTab(tester, 'Accounts');
    await tester.tap(find.text('Cash'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('account-icon-pick')));
    await settle(tester);
    expect(find.byKey(const ValueKey('account-icon-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('account-icon-remove')), findsNothing);
    await unmount(tester);
  });

  // ---- Plan / Fact icons ------------------------------------------------------

  testWidgets('Overview uses the Plan and Fact icons, not the words', (
    tester,
  ) async {
    await pump(
      tester,
      const BudgetScreen(),
      seed: () async {
        final b = BudgetService(db);
        final acc = await b.saveAccount(
          name: 'Euro',
          currency: 'EUR',
          rateToBase: 1,
        );
        final cat = await b.saveCategory(
          const CategoryInput(name: 'Groceries', price: 25, unitsPerMonth: 4),
        );
        await b.saveCategory(
          CategoryInput(
            id: cat,
            name: 'Groceries',
            price: 25,
            unitsPerMonth: 4,
            accountCountId: acc,
          ),
        );
      },
    );
    expect(paramIcon(Param.plan), findsWidgets);
    expect(paramIcon(Param.actual), findsWidgets);
    // The figures carry no leading "Plan ·" / "Fact ·" words.
    expect(find.textContaining('Plan ·'), findsNothing);
    expect(find.textContaining('Fact ·'), findsNothing);
    expect(find.text('Plan above actual'), findsNothing);
    await unmount(tester);
  });

  testWidgets('tapping the Plan icon shows its name', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: ParamIcon.plan())),
      ),
    );
    await tester.tap(find.byType(ParamIcon));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Plan'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  // ---- transactions ------------------------------------------------------------

  testWidgets('a transaction shows name, category line, quantity x price', (
    tester,
  ) async {
    late String txId;
    await pump(
      tester,
      const BudgetScreen(),
      seed: () async {
        final b = BudgetService(db);
        final cat = await b.saveCategory(
          const CategoryInput(name: 'Groceries', price: 25),
        );
        txId = await b.createTransaction(
          categoryId: cat,
          name: 'Milk and bread',
          quantity: 2,
          unitPrice: 25,
        );
      },
    );
    await openTab(tester, 'Transactions');
    final tile = find.byKey(ValueKey('budget-tx-$txId'));
    expect(
      find.descendant(of: tile, matching: find.text('Milk and bread')),
      findsOneWidget,
    );
    // Line 2: the categories icon and the category name.
    final catLine = find.byKey(ValueKey('budget-tx-category-$txId'));
    expect(
      find.descendant(of: catLine, matching: find.text('Groceries')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: catLine, matching: paramIcon(Param.categories)),
      findsOneWidget,
    );
    // Line 3: quantity x price.
    expect(
      find.descendant(of: tile, matching: find.text('2 × 25')),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('the options panel filters by account and by date range', (
    tester,
  ) async {
    final old = DateTime.utc(2026, 6, 10, 9);
    late String a1, a2;
    await pump(
      tester,
      const BudgetScreen(),
      seed: () async {
        final b = BudgetService(db);
        a1 = await b.saveAccount(name: 'Euro', currency: 'EUR', rateToBase: 1);
        a2 = await b.saveAccount(name: 'Lira', currency: 'TRY', rateToBase: 40);
        final c1 = await b.saveCategory(
          CategoryInput(
            name: 'Food',
            price: 5,
            accountCountId: a1,
            accountUseId: a1,
          ),
        );
        final c2 = await b.saveCategory(
          CategoryInput(
            name: 'Fuel',
            price: 7,
            // Counted in one account, paid through another: the filter
            // follows the account the money moves through (a2).
            accountCountId: a1,
            accountUseId: a2,
          ),
        );
        await b.createTransaction(categoryId: c1, name: 'Bread');
        await b.createTransaction(categoryId: c2, name: 'Petrol', date: old);
      },
    );
    await openTab(tester, 'Transactions');
    expect(find.text('Bread'), findsOneWidget);
    expect(find.text('Petrol'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('budget-tx-options-toggle')));
    await settle(tester);
    // Account filter: only the Lira account.
    await tester.ensureVisible(find.byKey(ValueKey('tx-filter-account-$a2')));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey('tx-filter-account-$a2')));
    await settle(tester);
    expect(find.text('Bread'), findsNothing);
    expect(find.text('Petrol'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('tx-filters-reset')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tx-filters-reset')));
    await settle(tester);
    expect(find.text('Bread'), findsOneWidget);

    // Date range: "from" a day after the old transaction leaves only the new one.
    await tester.ensureVisible(find.byKey(const ValueKey('tx-date-from')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tx-date-from')));
    await tester.pumpAndSettle();
    // The date picker opens on today; confirm it (today is after June 2026).
    await tester.tap(find.text('OK'));
    await settle(tester);
    expect(find.text('Bread'), findsOneWidget);
    expect(find.text('Petrol'), findsNothing);

    // A quick choice replaces the dates: "Today" keeps only the new one.
    await tester.tap(find.byKey(const ValueKey('tx-date-quick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tx-date-quick-today')));
    await settle(tester);
    expect(find.byKey(const ValueKey('tx-date-preset')), findsOneWidget);
    expect(find.text('Bread'), findsOneWidget);
    expect(find.text('Petrol'), findsNothing);
    // "Next year" matches neither.
    await tester.tap(find.byKey(const ValueKey('tx-date-quick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tx-date-quick-nextYear')));
    await settle(tester);
    expect(find.text('Bread'), findsNothing);
    // Removing the chip drops the whole date filter.
    await tester.tap(find.byTooltip('Remove the quick choice'));
    await settle(tester);
    expect(find.byKey(const ValueKey('tx-date-preset')), findsNothing);
    expect(find.text('Bread'), findsOneWidget);
    await unmount(tester);
    expect(a1, isNotEmpty);
  });

  testWidgets('deleting a transaction can be undone by the Undo history', (
    tester,
  ) async {
    late String txId;
    await pump(
      tester,
      const BudgetScreen(),
      seed: () async {
        final b = BudgetService(db);
        final cat = await b.saveCategory(
          const CategoryInput(name: 'Food', price: 5),
        );
        txId = await b.createTransaction(categoryId: cat, name: 'Bread');
      },
    );
    await openTab(tester, 'Transactions');
    // Delete lives in the transaction's edit dialog now (no icon on the row).
    expect(find.byKey(ValueKey('budget-delete-tx-$txId')), findsNothing);
    await tester.tap(find.byKey(ValueKey('budget-tx-$txId')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('tx-delete')));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400)); // the dialog closes
    expect(find.text('Bread'), findsNothing);
    expect(find.text('Deleted transaction'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(find.text('Bread'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await unmount(tester);
  });

  // ---- category dialog -----------------------------------------------------------

  testWidgets(
    'a GROUP category hides the ignored fields; Save/Cancel stay visible above the keyboard',
    (tester) async {
      late BudgetCategory group;
      await pump(
        tester,
        const Scaffold(),
        size: const Size(375, 812),
        seed: () async {
          final b = BudgetService(db);
          final parent = await b.saveCategory(
            const CategoryInput(name: 'Health'),
          );
          await b.saveCategory(
            CategoryInput(name: 'Massage', price: 10, parentId: parent),
          );
          group = await (db.select(
            db.budgetCategoriesTable,
          )..where((t) => t.id.equals(parent))).getSingle();
        },
      );
      // The keyboard is up: 300 px of the bottom is taken.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      final context = tester.element(find.byType(Scaffold));
      BudgetCategoryDialog.show(context, existing: group);
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Unit of measure'), findsNothing);
      expect(find.byKey(const ValueKey('category-price')), findsNothing);
      expect(find.byKey(const ValueKey('category-units')), findsNothing);
      // Save and Cancel are on screen, above the keyboard.
      final save = tester.getRect(find.byKey(const ValueKey('category-save')));
      expect(save.bottom, lessThanOrEqualTo(812 - 300));
      expect(save.top, greaterThanOrEqualTo(0));
      final cancel = tester.getRect(find.text('Cancel'));
      // ... and the buttons do not overlap the form fields.
      final name = tester.getRect(find.byKey(const ValueKey('category-name')));
      expect(name.overlaps(save), isFalse);
      expect(name.overlaps(cancel), isFalse);
      await unmount(tester);
    },
  );

  testWidgets('a leaf category still shows its unit, price and units', (
    tester,
  ) async {
    late BudgetCategory leaf;
    await pump(
      tester,
      const Scaffold(),
      size: const Size(1000, 1000),
      seed: () async {
        final id = await BudgetService(db)
            .saveCategory(const CategoryInput(name: 'Milk', price: 2));
        leaf = await (db.select(
          db.budgetCategoriesTable,
        )..where((t) => t.id.equals(id))).getSingle();
      },
    );
    final context = tester.element(find.byType(Scaffold));
    BudgetCategoryDialog.show(context, existing: leaf);
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Unit of measure'), findsOneWidget);
    expect(find.byKey(const ValueKey('category-price')), findsOneWidget);
    await unmount(tester);
    expect(dateTimeToDb(DateTime.utc(2026)), isNotNull);
  });
}
