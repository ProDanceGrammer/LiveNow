import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/ids.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/screens/actions_section.dart';
import 'package:livenow/ui/screens/templates_screen.dart';
import 'package:livenow/ui/widgets/action_editor.dart';
import 'package:livenow/ui/widgets/action_import_summary_dialog.dart';
import 'package:livenow/ui/widgets/notes_editor.dart';

const _csv = '''
Name,Datetime,Next actions and time,Previous actions and time,Growth Direction
😴 Сон,03/10/2026 23:00 → 04/10/2026 8:00,,,Невідомий
💧 Вода,03/10/2026,,,
''';

void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;

  Future<void> pump(WidgetTester tester, {String? csv}) async {
    // Wide window: below 900 px the app switches to the phone layout, which
    // hides the Import CSV button (Settings has it there).
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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

  testWidgets('Start now shows a toast whose name opens the created action', (
    tester,
  ) async {
    await pump(tester, csv: _csv);
    await tester.tap(find.byKey(const ValueKey('import-templates-csv')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('OK'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Start now').last);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    final toast = find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().startsWith('Started "'),
    );
    expect(toast, findsOneWidget);
    final plain = (tester.widget(toast) as RichText).text.toPlainText();
    final name = plain.substring(9, plain.length - 1);
    expect(
      (await tester.runAsync(() => db.select(db.actionsTable).get()))!
          .where((a) => a.name == name),
      hasLength(1),
    );

    // Tap the name span (inside the toast's text) -> editor opens.
    final paragraph = tester.renderObject<RenderParagraph>(toast);
    final box = paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: 9, extentOffset: 9 + name.length),
        )
        .first;
    await tester.tapAt(paragraph.localToGlobal(box.toRect().center));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ActionEditorDialog), findsOneWidget);
    await settleAndUnmount(tester);
  });

  Future<void> seedTemplate(
    WidgetTester tester,
    String name, {
    Map<String, dynamic> extra = const {},
  }) async {
    await tester.runAsync(
      () => db
          .into(db.actionTemplatesTable)
          .insert(
            ActionTemplatesTableCompanion.insert(
              id: newId(),
              name: name,
              payload: jsonEncode({'name': name, ...extra}),
            ),
          ),
    );
  }

  Future<void> refresh(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('templates are ordered by name ignoring leading emoji', (
    tester,
  ) async {
    await pump(tester);
    await seedTemplate(tester, '🙂 Banana');
    await seedTemplate(tester, 'cherry');
    await seedTemplate(tester, '↗️ Apple');
    await refresh(tester);
    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title as Text).data)
        .toList();
    expect(titles, ['↗️ Apple', '🙂 Banana', 'cherry']);
    await settleAndUnmount(tester);
  });

  testWidgets('search filters by name; No matches vs No templates yet.', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('No templates yet.'), findsOneWidget);
    await seedTemplate(tester, 'Заняття СПОРТОМ');
    await seedTemplate(tester, 'Walk');
    await refresh(tester);
    await tester.enterText(
      find.byKey(const ValueKey('templates-search')),
      'спортом',
    );
    await tester.pump();
    expect(find.text('Заняття СПОРТОМ'), findsOneWidget);
    expect(find.text('Walk'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('templates-search')),
      'zzz',
    );
    await tester.pump();
    expect(find.text('No matches'), findsOneWidget);
    expect(find.text('No templates yet.'), findsNothing);
    await settleAndUnmount(tester);
  });

  testWidgets('Delete asks first: Cancel keeps it, Delete removes it', (
    tester,
  ) async {
    await pump(tester);
    await seedTemplate(tester, 'Walk');
    await refresh(tester);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Delete template?'), findsOneWidget);
    expect(
      find.text('"Walk" will be deleted and cannot be restored.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      (await tester.runAsync(() => db.select(db.actionTemplatesTable).get()))!,
      hasLength(1),
    );

    await tester.tap(find.byTooltip('Delete'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('confirm-delete-template')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      (await tester.runAsync(() => db.select(db.actionTemplatesTable).get()))!,
      isEmpty,
    );
    await settleAndUnmount(tester);
  });

  testWidgets(
    'All day is compact and gaps separate Name / All day / Duration',
    (tester) async {
      await pump(tester);
      await tester.tap(find.byTooltip('New template'));
      await tester.pump(const Duration(milliseconds: 400));
      final name = tester.getRect(find.byType(TextFormField).first);
      final duration = tester.getRect(
        find.byKey(const ValueKey('template-duration')),
      );
      final sw = tester.getRect(find.byKey(const ValueKey('template-all-day')));
      expect(sw.top - name.bottom, greaterThanOrEqualTo(12));
      expect(duration.top - sw.bottom, greaterThanOrEqualTo(12));
      await settleAndUnmount(tester);
    },
  );

  testWidgets('template notes are saved, shown again and copied by Start now', (
    tester,
  ) async {
    const notes =
        '{"document":{"type":"page","children":[{"type":"paragraph","data":'
        '{"delta":[{"insert":"Buy Milk"}]}}]}}';
    await pump(tester);
    await seedTemplate(tester, 'Shop', extra: {'notes': notes});
    await refresh(tester);

    // Opening the editor expands Notes (it has text); saving keeps them.
    await tester.tap(find.text('Shop'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(NotesEditor), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    final saved = (await tester.runAsync(
      () => db.select(db.actionTemplatesTable).getSingle(),
    ))!;
    expect(jsonDecode(saved.payload)['notes'], isNotNull);

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Start now'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    final action = (await tester.runAsync(
      () => db.select(db.actionsTable).getSingle(),
    ))!;
    expect(action.notes, isNotNull);
    expect(action.notesText, contains('buy milk'));
    await tester.pump(const Duration(seconds: 6));
    await settleAndUnmount(tester);
  });

  Future<List<ActionRow>> allActions(WidgetTester tester) async =>
      (await tester.runAsync(() => db.select(db.actionsTable).get()))!;

  Future<void> tapAndWait(WidgetTester tester, Finder f) async {
    await tester.runAsync(() async {
      await tester.tap(f);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
  }

  testWidgets('Finish now creates a done action; toast says Finished "..." '
      'and Undo deletes it', (tester) async {
    await pump(tester);
    await seedTemplate(tester, 'Walk', extra: {'estimatedMinutes': 30});
    await refresh(tester);
    expect(find.text('Use'), findsNothing);
    expect(find.byTooltip('Start now'), findsOneWidget);

    await tapAndWait(tester, find.byTooltip('Finish now'));
    final toast = find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().startsWith('Finished "'),
    );
    expect(toast, findsOneWidget);
    final plain = (tester.widget(toast) as RichText).text.toPlainText();
    expect(plain.substring(10, plain.length - 1), 'Walk');
    final created = await allActions(tester);
    expect(created, hasLength(1));
    expect(created.single.done, isTrue);
    final occ = (await tester.runAsync(
      () => db.select(db.actionOccurrencesTable).get(),
    ))!;
    expect(occ.single.outcome, 'done');

    await tapAndWait(tester, find.text('Undo'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    expect(await allActions(tester), isEmpty);
    await tester.pump(const Duration(seconds: 6));
    await settleAndUnmount(tester);
  });

  testWidgets('Start now on an all-day template makes an undone all-day '
      'action; Finish now a done one', (tester) async {
    await pump(tester);
    await seedTemplate(tester, 'Water', extra: {'isAllDay': true});
    await refresh(tester);

    await tapAndWait(tester, find.byTooltip('Start now'));
    var rows = await allActions(tester);
    expect(rows.single.isAllDay, isTrue);
    expect(rows.single.done, isFalse);
    expect(rows.single.endAt, isNull);

    await tapAndWait(tester, find.byTooltip('Finish now'));
    rows = await allActions(tester);
    expect(rows, hasLength(2));
    expect(rows.where((r) => r.done), hasLength(1));
    expect(rows.every((r) => r.isAllDay), isTrue);
    await tester.pump(const Duration(seconds: 6));
    await settleAndUnmount(tester);
  });

  testWidgets('a started template with a deleted direction still starts', (
    tester,
  ) async {
    await pump(tester);
    await seedTemplate(
      tester,
      'Walk',
      extra: {
        'metricIds': ['gone'],
      },
    );
    await refresh(tester);
    await tapAndWait(tester, find.byTooltip('Start now'));
    expect(await allActions(tester), hasLength(1));
    await tester.pump(const Duration(seconds: 6));
    await settleAndUnmount(tester);
  });

  testWidgets('a template without notes has no notes in its payload', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byTooltip('New template'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextFormField).first, 'Plain');
    await tester.tap(find.text('Save'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    final saved = (await tester.runAsync(
      () => db.select(db.actionTemplatesTable).getSingle(),
    ))!;
    expect(jsonDecode(saved.payload).containsKey('notes'), isFalse);
    await settleAndUnmount(tester);
  });
}
