import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/screens/actions_section.dart';
import 'package:livenow/ui/screens/templates_screen.dart';
import 'package:livenow/ui/widgets/action_import_summary_dialog.dart';

const _csv = '''
Name,Datetime,Next actions and time,Previous actions and time,Growth Direction
😴 Сон,03/10/2026 23:00 → 04/10/2026 8:00,,,Невідомий
💧 Вода,03/10/2026,,,
''';

void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;

  Future<void> pump(WidgetTester tester, {String? csv}) async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionsCsvPickerProvider.overrideWithValue(() async => csv),
        ],
        child: const MaterialApp(home: TemplatesScreen()),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
  }

  Future<void> settleAndUnmount(WidgetTester tester) async {
    resetStackedDialogsForTest();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('Import CSV button creates templates and shows the summary', (
    tester,
  ) async {
    await pump(tester, csv: _csv);
    await tester.tap(find.byKey(const ValueKey('import-templates-csv')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(TemplateImportSummaryDialog), findsOneWidget);
    expect(find.text('2 templates created'), findsOneWidget);
    expect(find.text('Невідомий'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('9 h'), findsOneWidget); // tile shows the duration
    await settleAndUnmount(tester);
  });

  testWidgets('template editor saves the Duration field', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('New template'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextFormField).first, 'Walk');
    await tester.enterText(
      find.byKey(const ValueKey('template-duration')),
      '45',
    );
    await tester.tap(find.text('Save'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 400));

    final saved = (await tester.runAsync(
      () => db.select(db.actionTemplatesTable).get(),
    ))!;
    expect(jsonDecode(saved.single.payload)['estimatedMinutes'], 45);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('45 min'), findsOneWidget);
    await settleAndUnmount(tester);
  });
}
